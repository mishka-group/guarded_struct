defmodule GuardedStruct.Derive.Extension do
  @moduledoc """
  Define custom derive validators / sanitizers via a Spark DSL.

  ## Usage

      defmodule MyApp.Derives do
        use GuardedStruct.Derive.Extension

        derives do
          validator :slug, fn input ->
            is_binary(input) and Regex.match?(~r/^[a-z0-9-]+$/, input)
          end

          sanitizer :slugify, fn input when is_binary(input) ->
            input
            |> String.downcase()
            |> String.replace(~r/[^a-z0-9-]+/u, "-")
          end
        end
      end

  Register globally in `config/config.exs`:

      config :guarded_struct, derive_extensions: [MyApp.Derives]

  Then any GuardedStruct module can use the new ops:

      defmodule Post do
        use GuardedStruct

        guardedstruct do
          field :slug, String.t(), derives: "sanitize(slugify) validate(slug)"
        end
      end

  ## Validator return shape

  Validator functions return:

    * `true` — input passes
    * `false` — input fails (default error message generated)
    * `{:error, field, action, message}` — explicit error tuple
    * any other value — used as the validated value (for coercing validators)

  ## Introspection

  The `derives do ... end` block is introspectable via
  `Spark.Dsl.Extension.get_entities/2`. Verifiers and transformers can
  plug in at the standard Spark extension points.
  """

  use Spark.Dsl,
    default_extensions: [extensions: [GuardedStruct.Derive.Extension.Dsl]]

  @cache_key {__MODULE__, :registered_cache}

  @doc false
  def __dispatch_validator__(true, input, _field, _name), do: input

  def __dispatch_validator__(false, _input, field, name) do
    {:error, field, name, "Invalid format in the #{field} field (#{name})"}
  end

  def __dispatch_validator__({:error, _, _, _} = e, _input, _field, _name), do: e

  def __dispatch_validator__(other, _input, _field, _name), do: other

  @doc """
  Resolved list of registered extension modules from `:guarded_struct,
  :derive_extensions` application config.

  Cached in `:persistent_term` and invalidated automatically when the
  underlying config changes (e.g. between test cases that call
  `Application.put_env/3`).
  """
  def registered_extensions do
    raw = global_extensions()

    case :persistent_term.get(@cache_key, :__miss__) do
      {^raw, resolved} -> resolved
      _ -> recompute_cache(raw)
    end
  end

  @doc """
  Clear the cached extension list. Call from test setup if you mutate
  `:guarded_struct, :derive_extensions` and need the change visible
  before the next `registered_extensions/0` call.
  """
  def clear_cache do
    :persistent_term.erase(@cache_key)
    :ok
  end

  defp global_extensions, do: Application.get_env(:guarded_struct, :derive_extensions, [])

  defp recompute_cache(raw) do
    resolved = load_extensions(raw)
    :persistent_term.put(@cache_key, {raw, resolved})
    resolved
  end

  defp load_extensions(list) do
    list
    |> List.wrap()
    |> Enum.filter(&ensure_extension_loaded?/1)
    |> Enum.filter(&function_exported?(&1, :__derive_extension__?, 0))
  end

  # `Code.ensure_compiled?/1` (not `ensure_loaded?`) handles the case
  # where the extension and a module using it live in the same source
  # file — the .beam isn't on disk yet during the parent's compile pass.
  defp ensure_extension_loaded?(mod) when is_atom(mod) do
    match?({:module, _}, Code.ensure_compiled(mod))
  end

  defp ensure_extension_loaded?(_), do: false

  @doc """
  Resolve a per-module `derive_extensions:` opt — the raw list user wrote
  in `use GuardedStruct, derive_extensions: [...]` — into a flat list of
  extension modules with `:config` expanded to the current global config
  at the position it appears.

  ## Resolution rules

    * `nil` → fall back to the global Application config (no per-module opt set)
    * `[]` → no extensions at all (intentional opt-out, ignores global)
    * `[A, B]` (no `:config`) → these only; global is ignored
    * `[:config, A]` → global ++ [A] (global wins on op-name collisions)
    * `[A, :config]` → [A] ++ global (A wins on op-name collisions)
    * `[A, :config, B]` → [A] ++ global ++ [B]
  """
  @spec resolve_opt(list() | nil) :: [module()]
  def resolve_opt(nil), do: registered_extensions()

  def resolve_opt(list) when is_list(list) do
    list
    |> Enum.flat_map(fn
      :config -> global_extensions()
      mod when is_atom(mod) -> [mod]
    end)
    |> load_extensions()
  end

  @doc """
  Resolve the effective extension list for a specific user module.
  """
  @spec extensions_for(module() | nil) :: [module()]
  def extensions_for(nil), do: registered_extensions()

  def extensions_for(module) when is_atom(module) do
    case module.__guarded_derive_extensions_opt__() do
      nil -> registered_extensions()
      opt -> resolve_opt(opt)
    end
  end

  @doc """
  Validate a `derive_extensions:` opt list at compile time. Raises
  `ArgumentError` if entries are not modules / `:config`, or if `:config`
  appears more than once.
  """
  def validate_opt!(nil), do: nil

  def validate_opt!(list) when is_list(list) do
    Enum.each(list, fn
      :config ->
        :ok

      mod when is_atom(mod) ->
        :ok

      other ->
        raise ArgumentError,
              "derive_extensions: entries must be modules or :config, got #{inspect(other)}"
    end)

    config_count = Enum.count(list, &(&1 == :config))

    if config_count > 1 do
      raise ArgumentError,
            "derive_extensions: contains :config more than once; specify it exactly once or remove it"
    end

    list
  end

  def validate_opt!(other) do
    raise ArgumentError,
          "derive_extensions: expected a list, got #{inspect(other)}"
  end

  @doc """
  The user module currently being built. Set by `Runtime.with_telemetry/2`
  around every top-level `builder/1` call; nested sub_field builds inherit
  via the process dictionary.
  """
  def current_module, do: Process.get(:guarded_struct_current_module)

  @doc "Try the current module's extensions for a validator op."
  def dispatch_validate(op, input, field) do
    dispatch_validate(op, input, field, extensions_for(current_module()))
  end

  @doc "Try a specific list of extensions for a validator op."
  def dispatch_validate(op, input, field, extensions) when is_list(extensions) do
    Enum.reduce_while(extensions, :__not_found__, fn mod, _ ->
      case mod.__validate__(op, input, field) do
        :__not_found__ -> {:cont, :__not_found__}
        result -> {:halt, result}
      end
    end)
  end

  @doc "Try the current module's extensions for a sanitizer op."
  def dispatch_sanitize(op, input) do
    dispatch_sanitize(op, input, extensions_for(current_module()))
  end

  @doc "Try a specific list of extensions for a sanitizer op."
  def dispatch_sanitize(op, input, extensions) when is_list(extensions) do
    Enum.find_value(extensions, :__not_found__, fn mod ->
      if op in mod.__sanitizers__(), do: mod.__sanitize__(op, input)
    end)
  end

  @doc """
  All validator op atoms known across every extension visible from the
  given module.
  """
  def all_extension_validators(module \\ nil) do
    extensions_for(module)
    |> Enum.flat_map(& &1.__validators__())
    |> MapSet.new()
  end

  @doc "All sanitizer op atoms known across every extension visible from `module`."
  def all_extension_sanitizers(module \\ nil) do
    extensions_for(module)
    |> Enum.flat_map(& &1.__sanitizers__())
    |> MapSet.new()
  end
end
