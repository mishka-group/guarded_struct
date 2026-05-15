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

    {new_entities, warnings} =
      Enum.map_reduce(entities, [], fn entity, acc ->
        {parsed, w} = parse_entity(entity, module)
        {parsed, w ++ acc}
      end)

    new_dsl_state =
      Enum.reduce(new_entities, dsl_state, fn new_entity, acc ->
        Transformer.replace_entity(acc, [:guardedstruct], new_entity, fn old ->
          old.name == new_entity.name and old.__struct__ == new_entity.__struct__
        end)
      end)

    case warnings do
      [] -> {:ok, new_dsl_state}
      _ -> {:warn, new_dsl_state, Enum.reverse(warnings)}
    end
  end

  defp parse_entity(%Field{} = f, module) do
    {derive, warnings} = resolve(f, module)
    {%{f | __derive_ops__: parse_or_raise(derive, f.name, module)}, warnings}
  end

  defp parse_entity(%VirtualField{} = vf, module) do
    {derive, warnings} = resolve(vf, module)
    {%{vf | __derive_ops__: parse_or_raise(derive, vf.name, module)}, warnings}
  end

  defp parse_entity(%SubField{} = sf, module) do
    {derive, warnings} = resolve(sf, module)
    {fields, w1} = walk_children(sf.fields, module)
    {sub_fields, w2} = walk_children(sf.sub_fields, module)
    {conditional_fields, w3} = walk_children(sf.conditional_fields, module)

    parsed = %{
      sf
      | __derive_ops__: parse_or_raise(derive, sf.name, module),
        fields: fields,
        sub_fields: sub_fields,
        conditional_fields: conditional_fields
    }

    {parsed, warnings ++ w1 ++ w2 ++ w3}
  end

  defp parse_entity(%ConditionalField{} = cf, module) do
    {derive, warnings} = resolve(cf, module)
    {fields, w1} = walk_children(cf.fields, module)
    {sub_fields, w2} = walk_children(cf.sub_fields, module)
    {conditional_fields, w3} = walk_children(cf.conditional_fields, module)

    parsed = %{
      cf
      | __derive_ops__: parse_or_raise(derive, cf.name, module),
        fields: fields,
        sub_fields: sub_fields,
        conditional_fields: conditional_fields
    }

    {parsed, warnings ++ w1 ++ w2 ++ w3}
  end

  defp parse_entity(other, _module), do: {other, []}

  defp walk_children(entities, module) do
    Enum.map_reduce(entities, [], fn entity, acc ->
      {parsed, w} = parse_entity(entity, module)
      {parsed, w ++ acc}
    end)
  end

  # Prefer `derives:` (canonical). Fall back to legacy `derive:` and surface a
  # soft-deprecation warning via the transformer's `{:warn, ...}` return.
  defp resolve(%{derives: derives}, _module) when is_binary(derives) and derives != "",
    do: {derives, []}

  defp resolve(%{derive: derive, name: name} = _entity, module)
       when is_binary(derive) and derive != "" do
    warning =
      "`derive:` option on field #{inspect(name)} of #{inspect(module)} is deprecated. " <>
        "Use `derives:` instead. `derive:` will be removed in a future release."

    {derive, [warning]}
  end

  defp resolve(_entity, _module), do: {nil, []}

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
