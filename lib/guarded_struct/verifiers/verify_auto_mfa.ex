defmodule GuardedStruct.Verifiers.VerifyAutoMFA do
  @moduledoc false

  # Post-compile check: every `auto: {Mod, :fn}` (or `{Mod, :fn, default}`)
  # MFA must exist. Same rationale as VerifyValidatorMFA — runs after compile
  # to avoid forcing user modules into the compile graph.

  use Spark.Dsl.Verifier

  alias GuardedStruct.Transformers.Codegen
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    entities = Verifier.get_entities(dsl_state, [:guardedstruct])

    case entities |> Codegen.all_entities() |> Enum.reduce([], &check_auto/2) do
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

  defp check_auto(entity, acc) do
    case Map.get(entity, :auto) do
      {mod, fun} when is_atom(mod) and is_atom(fun) ->
        check(entity.name, mod, fun, 0, acc)

      {mod, fun, arg} when is_atom(mod) and is_atom(fun) ->
        check(entity.name, mod, fun, auto_arity(arg), acc)

      _ ->
        acc
    end
  end

  # `{Mod, :fn, [a, b]}` passes the list as the arguments; any other third element is
  # one argument.
  defp auto_arity(args) when is_list(args), do: length(args)
  defp auto_arity(_arg), do: 1

  defp check(field, mod, fun, arity, acc) do
    Code.ensure_loaded(mod)

    if function_exported?(mod, fun, arity) do
      acc
    else
      [{field, mod, fun, arity} | acc]
    end
  end
end
