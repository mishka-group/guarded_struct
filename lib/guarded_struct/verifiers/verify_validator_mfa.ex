defmodule GuardedStruct.Verifiers.VerifyValidatorMFA do
  @moduledoc false

  # Post-compile check: every `validator: {Mod, :fn}` MFA on every field must
  # exist. Verifiers run AFTER the user's module is fully compiled, so we can
  # `Code.ensure_loaded?` user code without dragging it into the compile-time
  # dependency graph.

  use Spark.Dsl.Verifier

  alias GuardedStruct.Transformers.Codegen
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    entities = Verifier.get_entities(dsl_state, [:guardedstruct])

    case entities |> Codegen.all_entities() |> Enum.reduce([], &check_validator/2) do
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

  defp check_validator(%{validator: {mod, fun}, name: name}, acc)
       when is_atom(mod) and is_atom(fun) do
    Code.ensure_loaded(mod)

    if function_exported?(mod, fun, 2) do
      acc
    else
      [{name, mod, fun} | acc]
    end
  end

  defp check_validator(_entity, acc), do: acc
end
