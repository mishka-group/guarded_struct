defmodule GuardedStruct.Derive.Extension do
  @moduledoc """
  Define custom derive validators / sanitizers as a small module-level DSL.

  ## Usage

      defmodule MyApp.Derives do
        use GuardedStruct.Derive.Extension

        validator :slug, fn input ->
          is_binary(input) and Regex.match?(~r/^[a-z0-9-]+$/, input)
        end

        sanitizer :slugify, fn input when is_binary(input) ->
          input
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9-]+/u, "-")
        end
      end

  Register globally in `config/config.exs`:

      config :guarded_struct, derive_extensions: [MyApp.Derives]

  Then any GuardedStruct module can use the new ops:

      defmodule Post do
        use GuardedStruct

        guardedstruct do
          field(:slug, String.t(), derives: "sanitize(slugify) validate(slug)")
        end
      end

  ## Validator return shape

  Validator functions return:

    * `true` — input passes
    * `false` — input fails (default error message generated)
    * `{:error, field, action, message}` — explicit error tuple
    * any other value — used as the validated value (for coercing validators)
  """

  defmacro __using__(_opts) do
    quote do
      import GuardedStruct.Derive.Extension, only: [validator: 2, sanitizer: 2]

      Module.register_attribute(__MODULE__, :__validator_ops__, accumulate: true)
      Module.register_attribute(__MODULE__, :__sanitizer_ops__, accumulate: true)

      @before_compile GuardedStruct.Derive.Extension
    end
  end

  @doc "Declare a validator op."
  defmacro validator(name, fun_ast) when is_atom(name) do
    __MODULE__.__warn_shadow__(:validate, name, __CALLER__)

    quote do
      @__validator_ops__ unquote(name)
      def __validate__(unquote(name), input, field) do
        GuardedStruct.Derive.Extension.__dispatch_validator__(
          unquote(fun_ast).(input),
          input,
          field,
          unquote(name)
        )
      end
    end
  end

  @doc false
  def __dispatch_validator__(true, input, _field, _name), do: input

  def __dispatch_validator__(false, _input, field, name) do
    {:error, field, name, "Invalid format in the #{field} field (#{name})"}
  end

  def __dispatch_validator__({:error, _, _, _} = e, _input, _field, _name), do: e

  def __dispatch_validator__(other, _input, _field, _name), do: other

  @doc "Declare a sanitizer op."
  defmacro sanitizer(name, fun_ast) when is_atom(name) do
    __MODULE__.__warn_shadow__(:sanitize, name, __CALLER__)

    quote do
      @__sanitizer_ops__ unquote(name)
      def __sanitize__(unquote(name), input) do
        unquote(fun_ast).(input)
      end
    end
  end

  @doc false
  # Compile-time check — if the custom op name collides with a built-in
  # registered in `Derive.Registry`, emit a Spark warning. The built-in's
  # pattern-matched function clause in `ValidationDerive` / `SanitizerDerive`
  # always wins, so the custom validator/sanitizer would be dead code.
  def __warn_shadow__(kind, name, caller) do
    shadows? =
      case kind do
        :validate -> GuardedStruct.Derive.Registry.known_validate?(name)
        :sanitize -> GuardedStruct.Derive.Registry.known_sanitize?(name)
      end

    if shadows? do
      Spark.Warning.warn(
        "#{kind_label(kind)} #{inspect(name)} in #{inspect(caller.module)} " <>
          "shadows a built-in `#{kind}(#{name})` op. Built-in clauses match first, " <>
          "so this custom #{kind_label(kind)} will NEVER be called. " <>
          "Rename it to avoid the shadow.",
        nil,
        Macro.Env.stacktrace(caller)
      )
    end

    :ok
  end

  defp kind_label(:validate), do: "validator"
  defp kind_label(:sanitize), do: "sanitizer"

  defmacro __before_compile__(_env) do
    quote do
      def __validators__, do: Enum.reverse(@__validator_ops__)
      def __sanitizers__, do: Enum.reverse(@__sanitizer_ops__)
      def __derive_extension__?, do: true

      def __validate__(_op, _input, _field), do: :__not_found__
      def __sanitize__(_op, input), do: input
    end
  end

  @doc """
  Returns the list of registered extension modules from app config.
  Loads each module and filters to only those that `use` this extension.
  """
  def registered_extensions, do: load_extensions(global_extensions())

  defp global_extensions, do: Application.get_env(:guarded_struct, :derive_extensions, [])

  defp load_extensions(list) do
    list
    |> List.wrap()
    |> Enum.filter(&ensure_extension_loaded?/1)
    |> Enum.filter(&function_exported?(&1, :__derive_extension__?, 0))
  end

  # `Code.ensure_compiled?/1` waits for in-flight compilation of the parent
  # module — required when an extension and the module using it live in the
  # SAME source file (e.g. `defmodule MyExt do ... end` and a sibling
  # `defmodule UsesIt do use GuardedStruct, derive_extensions: [MyExt] end`).
  # `Code.ensure_loaded?/1` would return false because the .beam file isn't
  # on disk yet during the parent's compile pass.
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
  Resolve the effective extension list for a specific user module. If the
  module declared a per-module opt via `use GuardedStruct, derive_extensions: [...]`,
  that takes precedence (with `:config` honoured); otherwise falls back to
  global config.
  """
  @spec extensions_for(module() | nil) :: [module()]
  def extensions_for(nil), do: registered_extensions()

  def extensions_for(module) when is_atom(module) do
    cond do
      function_exported?(module, :__guarded_derive_extensions_opt__, 0) ->
        resolve_opt(module.__guarded_derive_extensions_opt__())

      Code.ensure_loaded?(module) and
          function_exported?(module, :__guarded_derive_extensions_opt__, 0) ->
        resolve_opt(module.__guarded_derive_extensions_opt__())

      true ->
        registered_extensions()
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
  via the process dictionary. Returns `nil` for standalone callers like
  `GuardedStruct.Validate.run/2` that don't go through `builder/1`.
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
  given module (per-module + globally if opted in via `:config`).
  Used by the strict-mode compile-time check.
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
