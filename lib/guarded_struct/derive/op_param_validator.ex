defmodule GuardedStruct.Derive.OpParamValidator do
  @moduledoc false

  # Checks the parameters of parameterised derive ops. `check/3` returns
  # `:ok` or `{:error, message}`; `validate!/4` raises Spark.Error.DslError for
  # a module that is compiling. Examples of what it catches:
  #
  #   validate(max_len=foo)   — max_len needs an integer, got "foo"
  #   validate(min_len=-2)    — min_len needs a non-negative integer
  #   validate(record=42)     — record tag must be an atom-shaped string
  #
  # Bare atoms (e.g. :string, :not_empty) are not param-typed and pass.

  alias GuardedStruct.Derive.{OpEvaluator, Registry}

  @doc """
  Check the parameter types of an op-map (`%{validate: [...], sanitize: [...]}`).
  Returns `:ok`, or `{:error, message}` for the first problem found.

  ## Options

    * `:extra_validate` / `:extra_sanitize` — op names the inner ops of `each=` and
      `optional=` may use besides the built-in ones (see `Registry.known_validate?/2`):
      a list of atoms, `:any` when the module has a `validate_derive` / `sanitize_derive`
      module whose ops cannot be listed, or a function returning either. Defaults to `[]`.
  """
  @spec check(map() | nil, atom(), keyword()) :: :ok | {:error, String.t()}
  def check(ops, field_name, opts \\ [])

  def check(nil, _field_name, _opts), do: :ok

  def check(%{} = ops, field_name, opts) do
    ctx = %{
      extra: %{
        validate: Keyword.get(opts, :extra_validate, []),
        sanitize: Keyword.get(opts, :extra_sanitize, [])
      }
    }

    with :ok <- reject_invalid_operands(ops, field_name),
         :ok <- check_all(Map.get(ops, :validate, []), &check_validate(&1, field_name, ctx)) do
      check_all(Map.get(ops, :sanitize, []), &check_sanitize(&1, field_name, ctx))
    end
  end

  @doc """
  Like `check/3`, for a module that is compiling: raises Spark.Error.DslError on a
  problem and returns the input unchanged on success.
  """
  @spec validate!(map() | nil, atom(), module(), keyword()) :: map() | nil
  def validate!(ops, field_name, module, opts \\ [])

  def validate!(nil, _field_name, _module, _opts), do: nil

  def validate!(%{} = ops, field_name, module, opts) do
    case check(ops, field_name, opts) do
      :ok ->
        ops

      {:error, message} ->
        raise Spark.Error.DslError,
          message: message,
          path: [:guardedstruct, :field, field_name, :derive],
          module: module
    end
  end

  defp check_all(items, fun) do
    Enum.find_value(items, :ok, fn item ->
      case fun.(item) do
        :ok -> nil
        {:error, _message} = error -> error
      end
    end)
  end

  defp reject_invalid_operands(ops, field_name) do
    case find_invalid_operand(ops) do
      nil ->
        :ok

      source ->
        {:error,
         "could not parse the operand `#{source}` on field #{inspect(field_name)}. " <>
           "Write it as `op`, `op=value`, `op=[...]` or `equal=Type::value`."}
    end
  end

  defp find_invalid_operand({:invalid_operand, source}) when is_binary(source), do: source

  defp find_invalid_operand(%Regex{}), do: nil

  defp find_invalid_operand(%{} = map),
    do: map |> Map.values() |> find_invalid_operand()

  defp find_invalid_operand(list) when is_list(list),
    do: Enum.find_value(list, &find_invalid_operand/1)

  defp find_invalid_operand(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> find_invalid_operand()

  defp find_invalid_operand(_other), do: nil

  defp check_validate({:max_len, n}, _f, _m) when is_integer(n) and n >= 0, do: :ok

  defp check_validate({:max_len, other}, field_name, ctx),
    do: bad_param(:max_len, "non-negative integer", other, field_name, ctx)

  defp check_validate({:min_len, n}, _f, _m) when is_integer(n) and n >= 0, do: :ok

  defp check_validate({:min_len, other}, field_name, ctx),
    do: bad_param(:min_len, "non-negative integer", other, field_name, ctx)

  defp check_validate({:tell, n}, _f, _m) when is_integer(n), do: :ok

  defp check_validate({:tell, other}, field_name, ctx),
    do: bad_param(:tell, "integer (country code)", other, field_name, ctx)

  defp check_validate({:regex, %Regex{}}, _f, _m), do: :ok

  defp check_validate({:regex, value}, _f, _m)
       when is_list(value) or is_binary(value),
       do: :ok

  defp check_validate({:regex, other}, field_name, ctx),
    do: bad_param(:regex, "charlist, string, or compiled Regex", other, field_name, ctx)

  defp check_validate({:enum, list}, _f, _m) when is_list(list), do: :ok
  defp check_validate({:enum, "String[" <> _}, _f, _m), do: :ok
  defp check_validate({:enum, "Atom[" <> _}, _f, _m), do: :ok

  defp check_validate({:enum, "Integer[" <> _ = value}, field_name, ctx),
    do: check_operand_evaluates(:enum, value, "Integer[1::2]", field_name, ctx)

  defp check_validate({:enum, "Float[" <> _ = value}, field_name, ctx),
    do: check_operand_evaluates(:enum, value, "Float[1.5::2.5]", field_name, ctx)

  defp check_validate({:enum, "Map[" <> _ = value}, field_name, ctx),
    do: check_operand_evaluates(:enum, value, "Map[%{a: 1}::%{b: 2}]", field_name, ctx)

  defp check_validate({:enum, "Tuple[" <> _ = value}, field_name, ctx),
    do: check_operand_evaluates(:enum, value, "Tuple[{:a, 1}::{:b, 2}]", field_name, ctx)

  defp check_validate({:enum, other}, field_name, ctx),
    do:
      bad_param(
        :enum,
        "Type[…] form (String/Atom/Integer/Float/Map/Tuple)",
        other,
        field_name,
        ctx
      )

  defp check_validate({:equal, value}, _f, _m) when not is_binary(value), do: :ok
  defp check_validate({:equal, "String::" <> _}, _f, _m), do: :ok
  defp check_validate({:equal, "Atom::" <> _}, _f, _m), do: :ok

  defp check_validate({:equal, "Integer::" <> _ = value}, field_name, ctx),
    do: check_operand_evaluates(:equal, value, "Integer::42", field_name, ctx)

  defp check_validate({:equal, "Float::" <> _ = value}, field_name, ctx),
    do: check_operand_evaluates(:equal, value, "Float::1.5", field_name, ctx)

  defp check_validate({:equal, "Map::" <> _ = value}, field_name, ctx),
    do: check_operand_evaluates(:equal, value, "Map::%{a: 1}", field_name, ctx)

  defp check_validate({:equal, "Tuple::" <> _ = value}, field_name, ctx),
    do: check_operand_evaluates(:equal, value, "Tuple::{:a, 1}", field_name, ctx)

  defp check_validate({:equal, other}, field_name, ctx),
    do:
      bad_param(
        :equal,
        "Type::value form (String/Integer/Float/Atom/Map/Tuple)",
        other,
        field_name,
        ctx
      )

  defp check_validate({:record, tag}, _f, _m) when is_atom(tag), do: :ok
  defp check_validate({:record, tag}, _f, _m) when is_binary(tag), do: :ok

  defp check_validate({:record, other}, field_name, ctx),
    do: bad_param(:record, "atom or string tag", other, field_name, ctx)

  defp check_validate({:custom, {mods, fun}}, _f, _m)
       when is_list(mods) and is_atom(fun),
       do: :ok

  defp check_validate({:custom, {module, fun}}, _f, _m)
       when is_atom(module) and is_atom(fun),
       do: :ok

  defp check_validate({:custom, value}, _f, _m) when is_binary(value), do: :ok

  defp check_validate({:custom, other}, field_name, ctx),
    do: bad_param(:custom, "[Module.Path, :function_name] or string", other, field_name, ctx)

  defp check_validate(%{either: list}, field_name, ctx) when is_list(list) do
    check_all(list, &check_validate(&1, field_name, ctx))
  end

  defp check_validate({:optional, list}, field_name, ctx) when is_list(list),
    do: check_all(list, &check_combinator_inner(:validate, :optional, &1, field_name, ctx))

  defp check_validate({:optional, inner}, field_name, ctx) when is_atom(inner),
    do: check_combinator_inner(:validate, :optional, inner, field_name, ctx)

  defp check_validate({:optional, other}, field_name, ctx),
    do: bad_param(:optional, "atom op name or [op, op, …] list", other, field_name, ctx)

  defp check_validate(%{optional: list}, field_name, ctx) when is_list(list),
    do: check_all(list, &check_combinator_inner(:validate, :optional, &1, field_name, ctx))

  defp check_validate({:each, list}, field_name, ctx) when is_list(list),
    do: check_all(list, &check_combinator_inner(:validate, :each, &1, field_name, ctx))

  defp check_validate(%{each: list}, field_name, ctx) when is_list(list),
    do: check_all(list, &check_combinator_inner(:validate, :each, &1, field_name, ctx))

  defp check_validate({:each, other}, field_name, ctx),
    do: bad_param(:each, "[op, op, …] list of inner ops", other, field_name, ctx)

  defp check_validate(_other, _f, _m), do: :ok

  defp check_sanitize({:tag, sub_op}, _f, _m) when is_atom(sub_op) or is_binary(sub_op),
    do: :ok

  defp check_sanitize({:tag, other}, field_name, ctx),
    do: bad_param(:tag, "atom (e.g. :strip_tags) or string", other, field_name, ctx)

  defp check_sanitize({:clamp, [min, max]}, _f, _m)
       when is_number(min) and is_number(max) and min <= max,
       do: :ok

  defp check_sanitize({:clamp, other}, field_name, ctx),
    do: bad_param(:clamp, "[min, max] with min <= max (numbers)", other, field_name, ctx)

  defp check_sanitize({:default_when_nil, _value}, _f, _m), do: :ok
  defp check_sanitize({:default_when_empty, _value}, _f, _m), do: :ok

  defp check_sanitize({:each, list}, field_name, ctx) when is_list(list),
    do: check_all(list, &check_combinator_inner(:sanitize, :each, &1, field_name, ctx))

  defp check_sanitize(%{each: list}, field_name, ctx) when is_list(list),
    do: check_all(list, &check_combinator_inner(:sanitize, :each, &1, field_name, ctx))

  defp check_sanitize({:each, other}, field_name, ctx),
    do: bad_param(:each, "[op, op, …] list of inner sanitize ops", other, field_name, ctx)

  defp check_sanitize(_other, _f, _m), do: :ok

  # `OpEvaluator` turns a well-formed `Type[...]` / `Type::value` operand into its
  # value; one still written as text could not be evaluated.
  defp check_operand_evaluates(op, value, example, field_name, ctx) do
    case OpEvaluator.rewrite_tuple({op, value}) do
      {^op, evaluated} when not is_binary(evaluated) -> :ok
      _ -> bad_param(op, "a value that evaluates, like `#{example}`", value, field_name, ctx)
    end
  end

  defp check_combinator_inner(side, outer, arg, field_name, ctx) do
    case inner_op_name(arg) do
      nil ->
        bad_param(outer, "registered op atom or parameterised op tuple", arg, field_name, ctx)

      op ->
        if known_op?(side, op, ctx),
          do: recheck(side, arg, field_name, ctx),
          else: bad_inner_op(side, outer, op, field_name, ctx)
    end
  end

  defp inner_op_name(op) when is_atom(op), do: op
  defp inner_op_name({op, _}) when is_atom(op), do: op

  defp inner_op_name(%{} = map) when map_size(map) == 1 do
    case Map.keys(map) do
      [op] when is_atom(op) -> op
      _ -> nil
    end
  end

  defp inner_op_name(_), do: nil

  defp known_op?(:validate, op, ctx), do: Registry.known_validate?(op, ctx.extra.validate)
  defp known_op?(:sanitize, op, ctx), do: Registry.known_sanitize?(op, ctx.extra.sanitize)

  defp recheck(:validate, arg, field_name, ctx), do: check_validate(arg, field_name, ctx)
  defp recheck(:sanitize, arg, field_name, ctx), do: check_sanitize(arg, field_name, ctx)

  defp bad_inner_op(side, outer, op, field_name, _ctx) do
    {:error,
     "unknown #{side} op #{inspect(op)} inside `#{outer}` on field " <>
       "#{inspect(field_name)}. Define it with `GuardedStruct.Derive.Extension` " <>
       "or fix the typo."}
  end

  defp bad_param(op, expected, actual, field_name, _ctx) do
    {:error,
     "invalid parameter for `#{op}` on field #{inspect(field_name)}: " <>
       "expected #{expected}, got #{inspect(actual)}."}
  end
end
