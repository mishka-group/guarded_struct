defmodule GuardedStruct.Derive.Extension.Transformers.Codegen do
  @moduledoc false

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
      def __sanitize__(input, _op), do: input
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
      def __sanitize__(input, unquote(name)) do
        unquote(fun_ast).(input)
      end
    end
  end

  defp warn_shadows(validators, sanitizers, module) do
    Enum.each(validators, fn %Validator{name: name} = v ->
      if GuardedStruct.Derive.Registry.known_validate?(name) do
        Spark.Warning.warn(shadow_message(:validator, name, module), anno(v))
      end
    end)

    Enum.each(sanitizers, fn %Sanitizer{name: name} = s ->
      if GuardedStruct.Derive.Registry.known_sanitize?(name) do
        Spark.Warning.warn(shadow_message(:sanitizer, name, module), anno(s))
      end
    end)
  end

  defp shadow_message(kind, name, module) do
    op_kind = if kind == :validator, do: "validate", else: "sanitize"

    "#{kind} #{inspect(name)} in #{inspect(module)} shadows a built-in " <>
      "`#{op_kind}(#{name})` op. Built-in clauses match first, so this custom " <>
      "#{kind} will NEVER be called. Rename it to avoid the shadow."
  end

  defp anno(%{__spark_metadata__: %{anno: anno}}), do: anno
  defp anno(_), do: nil
end
