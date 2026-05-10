defmodule GuardedStruct.Transformers.ParseDerive do
  @moduledoc false

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer
  alias GuardedStruct.Dsl.{Field, SubField, ConditionalField, VirtualField}
  alias GuardedStruct.Derive.{Parser, OpEvaluator, OpParamValidator}

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
    %{f | __derive_ops__: parse_or_raise(resolve(f, module), f.name, module)}
  end

  defp parse_entity(%VirtualField{} = vf, module) do
    %{vf | __derive_ops__: parse_or_raise(resolve(vf, module), vf.name, module)}
  end

  defp parse_entity(%SubField{} = sf, module) do
    %{
      sf
      | __derive_ops__: parse_or_raise(resolve(sf, module), sf.name, module),
        fields: Enum.map(sf.fields, &parse_entity(&1, module)),
        sub_fields: Enum.map(sf.sub_fields, &parse_entity(&1, module)),
        conditional_fields: Enum.map(sf.conditional_fields, &parse_entity(&1, module))
    }
  end

  defp parse_entity(%ConditionalField{} = cf, module) do
    %{
      cf
      | __derive_ops__: parse_or_raise(resolve(cf, module), cf.name, module),
        fields: Enum.map(cf.fields, &parse_entity(&1, module)),
        sub_fields: Enum.map(cf.sub_fields, &parse_entity(&1, module)),
        conditional_fields: Enum.map(cf.conditional_fields, &parse_entity(&1, module))
    }
  end

  defp parse_entity(other, _module), do: other

  # Prefer `derives:` (canonical). Fall back to legacy `derive:` with a
  # soft-deprecation warning via Spark's deprecation helper.
  defp resolve(%{derives: derives}, _module) when is_binary(derives) and derives != "",
    do: derives

  defp resolve(%{derive: derive, name: name} = entity, module)
       when is_binary(derive) and derive != "" do
    warn_deprecated_derive(name, entity, module)
    derive
  end

  defp resolve(_entity, _module), do: nil

  defp warn_deprecated_derive(field_name, entity, module) do
    location = Map.get(entity, :__spark_metadata__) |> get_anno()

    Spark.Warning.warn_deprecated(
      "`derive:` option on field #{inspect(field_name)} of #{inspect(module)}",
      "Use `derives:` instead. `derive:` will be removed in a future release.",
      location,
      nil
    )
  end

  defp get_anno(%{anno: anno}), do: anno
  defp get_anno(_), do: nil

  defp parse_or_raise(nil, _field_name, _module), do: nil
  defp parse_or_raise("", _field_name, _module), do: nil

  defp parse_or_raise(str, field_name, module) when is_binary(str) do
    str
    |> Parser.parser()
    |> OpEvaluator.preevaluate()
    |> OpParamValidator.validate!(field_name, module)
  end

  defp parse_or_raise(other, field_name, module) do
    raise Spark.Error.DslError,
      message:
        "invalid derives on field #{inspect(field_name)}: expected a string, got #{inspect(other)}",
      path: [:guardedstruct, :field, field_name, :derives],
      module: module
  end
end
