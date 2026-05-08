defmodule GuardedStruct.Transformers.ParseCoreKeys do
  @moduledoc false

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer
  alias GuardedStruct.Dsl.{Field, SubField, ConditionalField, VirtualField}
  alias GuardedStruct.Derive.Parser

  @impl true
  def before?(GuardedStruct.Transformers.GenerateBuilder), do: true
  def before?(GuardedStruct.Transformers.GenerateSubFieldModules), do: true
  def before?(_), do: false

  @impl true
  def transform(dsl_state) do
    entities = Transformer.get_entities(dsl_state, [:guardedstruct])
    new_entities = Enum.map(entities, &parse/1)

    {:ok,
     Enum.reduce(new_entities, dsl_state, fn new_entity, acc ->
       Transformer.replace_entity(acc, [:guardedstruct], new_entity, fn old ->
         old.name == new_entity.name and old.__struct__ == new_entity.__struct__
       end)
     end)}
  end

  defp parse(%Field{} = f) do
    %{f | __from_path__: parse_path(f.from), __on_path__: parse_path(f.on)}
  end

  defp parse(%VirtualField{} = vf) do
    %{vf | __from_path__: parse_path(vf.from), __on_path__: parse_path(vf.on)}
  end

  defp parse(%SubField{} = sf) do
    %{
      sf
      | __from_path__: parse_path(sf.from),
        __on_path__: parse_path(sf.on),
        fields: Enum.map(sf.fields, &parse/1),
        sub_fields: Enum.map(sf.sub_fields, &parse/1),
        conditional_fields: Enum.map(sf.conditional_fields, &parse/1)
    }
  end

  defp parse(%ConditionalField{} = cf) do
    %{
      cf
      | __from_path__: parse_path(cf.from),
        __on_path__: parse_path(cf.on),
        fields: Enum.map(cf.fields, &parse/1),
        sub_fields: Enum.map(cf.sub_fields, &parse/1),
        conditional_fields: Enum.map(cf.conditional_fields, &parse/1)
    }
  end

  defp parse(other), do: other

  defp parse_path(nil), do: nil
  defp parse_path(""), do: nil
  defp parse_path(str) when is_binary(str), do: Parser.parse_core_keys_pattern(str)
  defp parse_path(_), do: nil
end
