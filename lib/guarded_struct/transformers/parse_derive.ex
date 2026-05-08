defmodule GuardedStruct.Transformers.ParseDerive do
  @moduledoc false

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer
  alias GuardedStruct.Dsl.{Field, SubField, ConditionalField, VirtualField}
  alias GuardedStruct.Derive.{Parser, OpEvaluator}

  @impl true
  def before?(GuardedStruct.Transformers.GenerateBuilder), do: true
  def before?(GuardedStruct.Transformers.GenerateSubFieldModules), do: true
  def before?(_), do: false

  @impl true
  def transform(dsl_state) do
    module = Transformer.get_persisted(dsl_state, :module)
    entities = Transformer.get_entities(dsl_state, [:guardedstruct])

    new_entities = Enum.map(entities, &parse_entity(&1, module))

    {:ok,
     Enum.reduce(new_entities, dsl_state, fn new_entity, acc ->
       Transformer.replace_entity(acc, [:guardedstruct], new_entity, fn old ->
         old.name == new_entity.name and old.__struct__ == new_entity.__struct__
       end)
     end)}
  end

  defp parse_entity(%Field{} = f, module) do
    %{f | __derive_ops__: parse_or_raise(f.derive, f.name, module)}
  end

  defp parse_entity(%VirtualField{} = vf, module) do
    %{vf | __derive_ops__: parse_or_raise(vf.derive, vf.name, module)}
  end

  defp parse_entity(%SubField{} = sf, module) do
    %{
      sf
      | __derive_ops__: parse_or_raise(sf.derive, sf.name, module),
        fields: Enum.map(sf.fields, &parse_entity(&1, module)),
        sub_fields: Enum.map(sf.sub_fields, &parse_entity(&1, module)),
        conditional_fields: Enum.map(sf.conditional_fields, &parse_entity(&1, module))
    }
  end

  defp parse_entity(%ConditionalField{} = cf, module) do
    %{
      cf
      | __derive_ops__: parse_or_raise(cf.derive, cf.name, module),
        fields: Enum.map(cf.fields, &parse_entity(&1, module)),
        sub_fields: Enum.map(cf.sub_fields, &parse_entity(&1, module)),
        conditional_fields: Enum.map(cf.conditional_fields, &parse_entity(&1, module))
    }
  end

  defp parse_entity(other, _module), do: other

  defp parse_or_raise(nil, _field_name, _module), do: nil
  defp parse_or_raise("", _field_name, _module), do: nil

  defp parse_or_raise(str, _field_name, _module) when is_binary(str) do
    str |> Parser.parser() |> OpEvaluator.preevaluate()
  end

  defp parse_or_raise(other, field_name, module) do
    raise Spark.Error.DslError,
      message:
        "invalid derive on field #{inspect(field_name)}: expected a string, got #{inspect(other)}",
      path: [:guardedstruct, :field, field_name, :derive],
      module: module
  end
end
