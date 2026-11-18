defmodule GuardedStruct.Verifiers.VerifySubFieldModules do
  @moduledoc false

  # Post-compile check: every module a sub_field generated is still the generated one.
  # A module with the same name defined later in the project replaces it, and the
  # parent's builder would then call a module that has no builder.

  use Spark.Dsl.Verifier

  alias GuardedStruct.Transformers.GenerateSubFieldModules
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    generated = Verifier.get_persisted(dsl_state, :guarded_sub_field_modules, [])

    case Enum.find(generated, fn {submodule, _name} -> replaced?(submodule) end) do
      nil ->
        :ok

      {submodule, name} ->
        {:error,
         Spark.Error.DslError.exception(
           message: GenerateSubFieldModules.taken_name_message(submodule, name),
           path: [:guardedstruct, :sub_field, name],
           module: module
         )}
    end
  end

  defp replaced?(submodule) do
    Code.ensure_loaded?(submodule) and not GenerateSubFieldModules.generated_sub_field?(submodule)
  end
end
