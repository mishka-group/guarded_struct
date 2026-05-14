defmodule GuardedStruct.Verifiers.VerifyAutoMFA do
  @moduledoc false

  # Post-compile check: every `auto: {Mod, :fn}` (or `{Mod, :fn, default}`)
  # MFA must exist. Same rationale as VerifyValidatorMFA — runs after compile
  # to avoid forcing user modules into the compile graph.

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

      [{field_name, mod, fun, arity} | _] ->
        {:error,
         Spark.Error.DslError.exception(
           message:
             "auto #{inspect(mod)}.#{fun}/#{arity} not exported (declared on field #{inspect(field_name)})",
           path: [:guardedstruct, :field, field_name, :auto],
           module: module
         )}
    end
  end

  defp walk(entities, errors) do
    Enum.reduce(entities, errors, fn entity, acc ->
      acc =
        case Map.get(entity, :auto) do
          {mod, fun} when is_atom(mod) and is_atom(fun) ->
            check(entity.name, mod, fun, 0, acc)

          {mod, fun, arg} when is_atom(mod) and is_atom(fun) ->
            arity = if is_list(arg), do: length(arg), else: 1
            check(entity.name, mod, fun, arity, acc)

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

  defp check(field, mod, fun, arity, acc) do
    Code.ensure_loaded(mod)

    if function_exported?(mod, fun, arity) do
      acc
    else
      [{field, mod, fun, arity} | acc]
    end
  end
end
