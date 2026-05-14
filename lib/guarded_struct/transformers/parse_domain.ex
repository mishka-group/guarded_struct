defmodule GuardedStruct.Transformers.ParseDomain do
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
    entities = Transformer.get_entities(dsl_state, [:guardedstruct])
    new_entities = Enum.map(entities, &parse/1)

    {:ok,
     Enum.reduce(new_entities, dsl_state, fn new_entity, acc ->
       Transformer.replace_entity(acc, [:guardedstruct], new_entity, fn old ->
         old.name == new_entity.name and old.__struct__ == new_entity.__struct__
       end)
     end)}
  end

  defp parse(%Field{} = f), do: %{f | __domain_ops__: parse_domain(f.domain)}
  defp parse(%VirtualField{} = vf), do: %{vf | __domain_ops__: parse_domain(vf.domain)}

  defp parse(%SubField{} = sf) do
    %{
      sf
      | __domain_ops__: parse_domain(sf.domain),
        fields: Enum.map(sf.fields, &parse/1),
        sub_fields: Enum.map(sf.sub_fields, &parse/1),
        conditional_fields: Enum.map(sf.conditional_fields, &parse/1)
    }
  end

  defp parse(%ConditionalField{} = cf) do
    %{
      cf
      | __domain_ops__: parse_domain(cf.domain),
        fields: Enum.map(cf.fields, &parse/1),
        sub_fields: Enum.map(cf.sub_fields, &parse/1),
        conditional_fields: Enum.map(cf.conditional_fields, &parse/1)
    }
  end

  defp parse(other), do: other

  defp parse_domain(nil), do: nil
  defp parse_domain(""), do: nil

  defp parse_domain(pattern) when is_binary(pattern) do
    pattern
    |> String.trim()
    |> String.split("::", trim: true)
    |> Enum.map(&parse_rule/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_domain(_), do: nil

  defp parse_rule(rule) do
    case String.split(rule, "=", parts: 2) do
      ["!" <> field_path, pattern] ->
        %{required?: true, field_path: field_path, validator: build_validator(pattern)}

      ["?" <> field_path, pattern] ->
        %{required?: false, field_path: field_path, validator: build_validator(pattern)}

      _ ->
        nil
    end
  end

  defp build_validator(pattern) do
    pattern |> convert_pattern() |> OpEvaluator.rewrite_tuple()
  end

  defp convert_pattern("Tuple" <> list), do: {:enum, "Tuple[#{eval_re_structure(list)}]"}
  defp convert_pattern("Map" <> list), do: {:enum, "Map[#{eval_re_structure(list)}]"}

  defp convert_pattern("Equal" <> data) do
    {:equal, data |> String.replace(["[", "]"], "") |> String.replace(">>", "::")}
  end

  defp convert_pattern("Either" <> list) do
    converted =
      list
      |> String.replace("enum>>", "enum=")
      |> String.replace(">>", "::")
      |> Code.string_to_quoted!()
      |> then(&Parser.convert_parameters("parsed_string", &1))

    %{either: converted["parsed_string"]}
  end

  defp convert_pattern("Custom" <> list), do: {:custom, list}
  defp convert_pattern(plain), do: {:enum, re_structure(plain)}

  defp re_structure(data) do
    data |> String.split(",", trim: true) |> Enum.map(&String.trim/1) |> Enum.join("::")
  end

  defp eval_re_structure(data) do
    {converted, []} = Code.eval_string(data)
    Enum.reduce(converted, "", fn item, acc -> acc <> "#{Macro.to_string(item)}::" end)
  end
end
