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
    quote do
      @__sanitizer_ops__ unquote(name)
      def __sanitize__(unquote(name), input) do
        unquote(fun_ast).(input)
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def __validators__, do: Enum.reverse(@__validator_ops__)
      def __sanitizers__, do: Enum.reverse(@__sanitizer_ops__)
      def __derive_extension__?, do: true

      def __validate__(_op, _input, _field), do: :__not_found__
      def __sanitize__(_op, input), do: input
    end
  end

  @doc "Returns the list of registered extension modules from app config."
  def registered_extensions do
    :guarded_struct
    |> Application.get_env(:derive_extensions, [])
    |> List.wrap()
    |> Enum.filter(&Code.ensure_loaded?/1)
    |> Enum.filter(&function_exported?(&1, :__derive_extension__?, 0))
  end

  @doc """
  Try each registered extension's `__validate__/3` until one returns a non-
  `:__not_found__` result.
  """
  def dispatch_validate(op, input, field) do
    Enum.reduce_while(registered_extensions(), :__not_found__, fn mod, _ ->
      case mod.__validate__(op, input, field) do
        :__not_found__ -> {:cont, :__not_found__}
        result -> {:halt, result}
      end
    end)
  end

  @doc "Try each registered extension's `__sanitize__/2`."
  def dispatch_sanitize(op, input) do
    Enum.find_value(registered_extensions(), :__not_found__, fn mod ->
      if op in mod.__sanitizers__(), do: mod.__sanitize__(op, input)
    end)
  end

  @doc "All validator op atoms registered across every extension."
  def all_extension_validators do
    registered_extensions()
    |> Enum.flat_map(& &1.__validators__())
    |> MapSet.new()
  end

  @doc "All sanitizer op atoms registered across every extension."
  def all_extension_sanitizers do
    registered_extensions()
    |> Enum.flat_map(& &1.__sanitizers__())
    |> MapSet.new()
  end
end
