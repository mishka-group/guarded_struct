defmodule GuardedStruct.Verifiers.VerifyValidatorMFA do
  @moduledoc false

  # Post-compile check: every `validator: {Mod, :fn}` MFA on every field must
  # exist. Verifiers run AFTER the user's module is fully compiled, so we can
  # `Code.ensure_loaded?` user code without dragging it into the compile-time
  # dependency graph.

  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias GuardedStruct.Dsl.{Field, SubField, ConditionalField}

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    entities = Verifier.get_entities(dsl_state, [:guardedstruct])

    case walk(entities, []) do
      [] ->
        :ok

      [{field_name, mod, fun} | _] ->
        {:error,
         Spark.Error.DslError.exception(
           message:
             "validator #{inspect(mod)}.#{fun}/2 not exported (declared on field #{inspect(field_name)})",
           path: [:guardedstruct, :field, field_name, :validator],
           module: module
         )}
    end
  end

  defp walk(entities, errors) do
    Enum.reduce(entities, errors, fn entity, acc ->
      acc =
        case Map.get(entity, :validator) do
          {mod, fun} when is_atom(mod) and is_atom(fun) ->
            Code.ensure_loaded(mod)

            if function_exported?(mod, fun, 2) do
              acc
            else
              [{entity.name, mod, fun} | acc]
            end

          _ ->
            acc
        end

      case entity do
        %SubField{} = sf ->
          walk(sf.fields ++ sf.sub_fields ++ sf.conditional_fields, acc)

        %ConditionalField{} = cf ->
          walk(cf.fields ++ cf.sub_fields ++ cf.conditional_fields, acc)

        %Field{} ->
          acc

        _ ->
          acc
      end
    end)
  end
end
