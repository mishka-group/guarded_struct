defmodule GuardedStruct.Validate do
  @moduledoc """
  Standalone validators that reuse a `GuardedStruct` schema without going
  through the full `builder/1` pipeline.

  Three tiers:

    * `run/2` — derive op-string against a single value, no module needed.
    * `field/3,4` — validate one named field of a `guardedstruct` module.
      Cross-field dependencies (`on:`, `domain:`) honoured by mode.
    * `partial/2` — validate a subset of fields together. Missing fields
      skipped (no `enforce_keys` check). Useful for form-as-you-type and
      PATCH-style endpoints.

  Returns the validated value (or partial map) on success, an error list
  with the same shape as `builder/1` on failure.
  """

  import GuardedStruct.Messages, only: [translated_message: 2]

  alias GuardedStruct.{Derive, Runtime}
  alias GuardedStruct.Derive.{Extension, Parser, OpEvaluator, OpParamValidator, ValidationDerive}

  @type error :: %{
          required(:field) => atom(),
          required(:action) => atom(),
          required(:message) => String.t(),
          optional(any()) => any()
        }

  @doc """
  Validate a value against a derive op-string. No module needed.

      iex> GuardedStruct.Validate.run("validate(string, max_len=80)", "hi")
      {:ok, "hi"}

  The string is checked the way a `derives:` string is when a module compiles.
  One that cannot be read, or whose operand is wrong, returns an error with the
  action `:bad_parameters` and the field `:__value__`.

      iex> {:error, [%{action: :bad_parameters}]} =
      ...>   GuardedStruct.Validate.run("validate(max_len=foo)", "x")
  """
  @spec run(String.t(), any()) :: {:ok, any()} | {:error, [error]}
  def run(derive_string, value) when is_binary(derive_string) do
    case read_derive(derive_string) do
      {:ok, nil} ->
        {:ok, value}

      {:ok, ops} ->
        input = %{field: :__value__, derive_ops: ops}

        case Derive.derive({:ok, %{__value__: value}, [input]}) do
          {:ok, %{__value__: validated}} -> {:ok, validated}
          {:error, errs} -> {:error, errs}
        end

      {:error, message} ->
        {:error, [%{field: :__value__, action: :bad_parameters, message: message}]}
    end
  end

  defp read_derive(derive_string) do
    case Parser.parse(derive_string) do
      {:ok, ops} ->
        with :ok <- OpParamValidator.check(ops, :__value__, extra_ops_opts()) do
          {:ok, OpEvaluator.preevaluate(ops)}
        end

      {:error, reason} ->
        {:error,
         "could not parse the derive string #{inspect(derive_string)}: #{reason}. " <>
           "Write ops as `op`, `op=value`, `op=[...]`, `enum=Type[a::b]` or `equal=Type::value`."}
    end
  end

  defp extra_ops_opts do
    [
      extra_validate: fn -> extra_ops(:validate_derive, &Extension.all_extension_validators/0) end,
      extra_sanitize: fn -> extra_ops(:sanitize_derive, &Extension.all_extension_sanitizers/0) end
    ]
  end

  defp extra_ops(option, extension_ops) do
    if Derive.fallback_modules(option) == [],
      do: MapSet.to_list(extension_ops.()),
      else: :any
  end

  @doc """
  Validate a single named field of a `guardedstruct` module.

  ## Modes

    * `:strict` (default) — honour `on:` and `domain:` core keys. Errors if
      a cross-field dependency can't be resolved.
    * `:isolated` — skip cross-field deps. Run only `derive:` + `validator:`.

  ## Context

  Pass `context: %{other_field: ...}` to provide values for cross-field
  dependency resolution.
  """
  @spec field(module(), atom(), any(), keyword()) :: {:ok, any()} | {:error, [error]}
  def field(module, field_name, value, opts \\ [])
      when is_atom(module) and is_atom(field_name) do
    case module.__field_meta__(field_name) do
      nil ->
        {:error,
         [
           %{
             field: field_name,
             action: :unknown_field,
             message: "field #{inspect(field_name)} is not defined on #{inspect(module)}"
           }
         ]}

      meta ->
        Runtime.with_current_module(module, fn -> do_field_validate(meta, value, opts, module) end)
    end
  end

  @doc """
  Validate a partial map of fields. Missing fields are skipped (no
  `enforce_keys` check). Cross-field deps resolve from the same input.
  """
  @spec partial(module(), map()) :: {:ok, map()} | {:error, [error]}
  def partial(_module, attrs) when not is_map(attrs) do
    {:error, [%{field: :__value__, action: :bad_parameters, message: "input must be a map"}]}
  end

  def partial(module, attrs) do
    attrs = Runtime.atomize(module, attrs)
    fields = module.__fields__()
    present = Enum.filter(fields, &Map.has_key?(attrs, &1.name))

    {ok_acc, err_acc} =
      Runtime.with_current_module(module, fn ->
        Enum.reduce(present, {%{}, []}, fn meta, {ok, errs} ->
          value = Map.get(attrs, meta.name)

          case do_field_validate(meta, value, [context: attrs, mode: :strict], module) do
            {:ok, validated} -> {Map.put(ok, meta.name, validated), errs}
            {:error, e} -> {ok, errs ++ List.wrap(e)}
          end
        end)
      end)

    if err_acc == [], do: {:ok, ok_acc}, else: {:error, err_acc}
  end

  defp do_field_validate(meta, value, opts, module) do
    mode = Keyword.get(opts, :mode, :strict)
    context = Keyword.get(opts, :context, %{})

    cross_field_check =
      case mode do
        :isolated -> :ok
        _ -> check_cross_field_deps(meta, context)
      end

    with :ok <- cross_field_check,
         {:ok, sanitized} <- run_pre_derive(meta, value),
         {:ok, validated} <- run_field_validator(meta, sanitized, module) do
      {:ok, validated}
    end
  end

  defp check_cross_field_deps(meta, context) do
    errors = []

    errors =
      case Map.get(meta, :__on_path__) || parse_path(Map.get(meta, :on)) do
        nil ->
          errors

        path ->
          if path_present?(path, context) do
            errors
          else
            errors ++
              [
                %{
                  field: meta.name,
                  action: :dependent_keys,
                  message: translated_message(:check_dependent_keys, {meta.name, path})
                }
              ]
          end
      end

    errors =
      case Map.get(meta, :__domain_ops__) do
        nil ->
          errors

        rules ->
          rules
          |> Enum.flat_map(fn rule -> run_domain_rule(rule, meta.name, context) end)
          |> Kernel.++(errors)
      end

    case errors do
      [] -> :ok
      errs -> {:error, errs}
    end
  end

  defp parse_path(nil), do: nil
  defp parse_path(""), do: nil
  defp parse_path(str) when is_binary(str), do: Parser.parse_core_keys_pattern(str)
  defp parse_path(_), do: nil

  defp path_present?([:root | rest], context) do
    not is_nil(get_in(context, rest))
  end

  defp path_present?(path, context) do
    not is_nil(get_in(context, path))
  end

  defp run_domain_rule(
         %{field_path: field_path, validator: validator, required?: required?},
         key,
         context
       ) do
    target =
      field_path
      |> String.split(".", trim: true)
      |> Enum.map(&String.to_existing_atom/1)
      |> then(&get_in(context, &1))

    cond do
      not is_nil(target) ->
        case ValidationDerive.validate(validator, target, key) do
          data when is_tuple(data) and elem(data, 0) == :error ->
            [
              %{
                field: key,
                action: :domain_parameters,
                message: translated_message(:domain_field_status, key)
              }
            ]

          _ ->
            []
        end

      not required? ->
        []

      true ->
        [
          %{
            field: key,
            action: :domain_parameters,
            message: translated_message(:force_domain_field_status, key)
          }
        ]
    end
  rescue
    _ -> []
  end

  defp run_pre_derive(%{__derive_ops__: ops, name: name}, value)
       when is_map(ops) and map_size(ops) > 0 do
    input = %{field: name, derive_ops: ops}

    case Derive.derive({:ok, %{name => value}, [input]}) do
      {:ok, %{^name => validated}} -> {:ok, validated}
      {:error, errs} -> {:error, errs}
    end
  end

  defp run_pre_derive(_meta, value), do: {:ok, value}

  defp run_field_validator(%{validator: {mod, fun}, name: name}, value, _module)
       when is_atom(mod) and is_atom(fun) do
    case apply(mod, fun, [name, value]) do
      {:ok, _, validated} ->
        {:ok, validated}

      {:ok, validated} ->
        {:ok, validated}

      {:error, _, message} ->
        {:error, [%{field: name, action: :validator, message: message}]}

      {:error, message} ->
        {:error, [%{field: name, action: :validator, message: message}]}

      _ ->
        {:ok, value}
    end
  end

  defp run_field_validator(%{name: name}, value, module) do
    if module.__guarded_has_validator__() do
      case module.validator(name, value) do
        {:ok, _, validated} ->
          {:ok, validated}

        {:ok, validated} ->
          {:ok, validated}

        {:error, _, message} ->
          {:error, [%{field: name, action: :validator, message: message}]}

        _ ->
          {:ok, value}
      end
    else
      {:ok, value}
    end
  end
end
