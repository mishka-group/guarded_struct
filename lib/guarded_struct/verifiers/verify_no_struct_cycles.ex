defmodule GuardedStruct.Verifiers.VerifyNoStructCycles do
  @moduledoc false

  use Spark.Dsl.Verifier

  alias GuardedStruct.Dsl.{Field, SubField, ConditionalField}

  @impl true
  def verify(dsl_state) do
    module = Spark.Dsl.Verifier.get_persisted(dsl_state, :module)
    entities = Spark.Dsl.Verifier.get_entities(dsl_state, [:guardedstruct])

    walk(module, entities, MapSet.new([module]))
    :ok
  end

  defp walk(origin, entities, visited) do
    Enum.each(entities, fn entity -> walk_entity(origin, entity, visited) end)
  end

  defp walk_entity(origin, %Field{struct: target}, visited)
       when is_atom(target) and not is_nil(target) do
    visit(origin, target, visited)
  end

  defp walk_entity(origin, %Field{structs: target}, visited)
       when is_atom(target) and target not in [nil, true, false] do
    visit(origin, target, visited)
  end

  defp walk_entity(origin, %SubField{} = sf, visited) do
    children = sf.fields ++ sf.sub_fields ++ sf.conditional_fields
    walk(origin, children, visited)
  end

  defp walk_entity(origin, %ConditionalField{} = cf, visited) do
    children = cf.fields ++ cf.sub_fields ++ cf.conditional_fields
    walk(origin, children, visited)
  end

  defp walk_entity(_origin, _other, _visited), do: :ok

  defp visit(origin, target, visited) do
    cond do
      target == origin ->
        raise_cycle(origin, [target])

      MapSet.member?(visited, target) ->
        :ok

      not function_exported?(target, :__fields__, 0) ->
        :ok

      true ->
        target_fields = target.__fields__()

        Enum.each(target_fields, fn meta ->
          case {Map.get(meta, :struct), Map.get(meta, :structs)} do
            {nil, nil} ->
              :ok

            {next, _} when is_atom(next) and not is_nil(next) ->
              if next == origin, do: raise_cycle(origin, [target, next])
              visit_via(origin, next, MapSet.put(visited, target))

            {_, next} when is_atom(next) and next not in [nil, true, false] ->
              if next == origin, do: raise_cycle(origin, [target, next])
              visit_via(origin, next, MapSet.put(visited, target))

            _ ->
              :ok
          end
        end)
    end
  end

  defp visit_via(origin, next, visited) do
    cond do
      MapSet.member?(visited, next) -> :ok
      not function_exported?(next, :__fields__, 0) -> :ok
      true -> visit(origin, next, visited)
    end
  end

  defp raise_cycle(origin, chain) do
    rendered = [origin | chain] |> Enum.map(&inspect/1) |> Enum.join(" → ")

    raise Spark.Error.DslError,
      message:
        "module reference cycle detected: #{rendered}.\n" <>
          "Two GuardedStruct modules cannot reference each other via `struct:` " <>
          "or `structs:` — building one would recursively build the other forever.\n" <>
          "Break the cycle by replacing one direction with a non-struct field " <>
          "(e.g. an id reference) and resolving the relation at runtime."
  end
end
