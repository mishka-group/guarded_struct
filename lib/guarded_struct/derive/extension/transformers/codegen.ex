defmodule GuardedStruct.Derive.Extension.Transformers.Codegen do
  @moduledoc false

  # Reads the `derives do ... end` entities and emits the
  # `__validate__/3`, `__sanitize__/2`, `__validators__/0`,
  # `__sanitizers__/0`, `__derive_extension__?/0` callbacks the rest of
  # the runtime expects. Mirrors the old `@before_compile` shape but is
  # driven by Spark entity state.

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer
  alias GuardedStruct.Derive.Extension.Dsl.{Validator, Sanitizer}

  @impl true
  def transform(dsl_state) do
    entities = Transformer.get_entities(dsl_state, [:derives])
    module = Transformer.get_persisted(dsl_state, :module)

    validators = Enum.filter(entities, &match?(%Validator{}, &1))
    sanitizers = Enum.filter(entities, &match?(%Sanitizer{}, &1))

    warn_shadows(validators, sanitizers, module)

    body = build_body(validators, sanitizers)
    {:ok, Transformer.eval(dsl_state, [], body)}
  end

  defp build_body(validators, sanitizers) do
    validator_names = Enum.map(validators, & &1.name)
    sanitizer_names = Enum.map(sanitizers, & &1.name)

    validator_clauses = Enum.map(validators, &validator_clause/1)
    sanitizer_clauses = Enum.map(sanitizers, &sanitizer_clause/1)

    quote do
      def __validators__, do: unquote(validator_names)
      def __sanitizers__, do: unquote(sanitizer_names)
      def __derive_extension__?, do: true

      unquote_splicing(validator_clauses)
      def __validate__(_op, _input, _field), do: :__not_found__

      unquote_splicing(sanitizer_clauses)
      def __sanitize__(_op, input), do: input
    end
  end

  defp validator_clause(%Validator{name: name, fun: fun_ast}) do
    quote do
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

  defp sanitizer_clause(%Sanitizer{name: name, fun: fun_ast}) do
    quote do
      def __sanitize__(unquote(name), input) do
        unquote(fun_ast).(input)
      end
    end
  end

  defp warn_shadows(validators, sanitizers, module) do
    Enum.each(validators, fn %Validator{name: name} ->
      if GuardedStruct.Derive.Registry.known_validate?(name) do
        IO.warn(
          "validator #{inspect(name)} in #{inspect(module)} shadows a built-in " <>
            "`validate(#{name})` op. Built-in clauses match first, so this custom " <>
            "validator will NEVER be called. Rename it to avoid the shadow.",
          []
        )
      end
    end)

    Enum.each(sanitizers, fn %Sanitizer{name: name} ->
      if GuardedStruct.Derive.Registry.known_sanitize?(name) do
        IO.warn(
          "sanitizer #{inspect(name)} in #{inspect(module)} shadows a built-in " <>
            "`sanitize(#{name})` op. Built-in clauses match first, so this custom " <>
            "sanitizer will NEVER be called. Rename it to avoid the shadow.",
          []
        )
      end
    end)
  end
end
