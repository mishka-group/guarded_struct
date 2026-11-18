defmodule GuardedStruct.Transformers.ParseCoreKeys do
  @moduledoc false

  use Spark.Dsl.Transformer

  alias GuardedStruct.Derive.{OpEvaluator, Parser}
  alias GuardedStruct.Dsl.{ConditionalField, Field, SubField, VirtualField}
  alias Spark.Dsl.Transformer

  @impl true
  def before?(GuardedStruct.Transformers.GenerateBuilder), do: true
  def before?(GuardedStruct.Transformers.GenerateAshValidator), do: true
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

  # Pre-parses the core keys of every entity, nested ones included: the `from:`
  # and `on:` paths and the `domain:` rules.
  defp parse(%Field{} = f), do: parse_keys(f)
  defp parse(%VirtualField{} = vf), do: parse_keys(vf)
  defp parse(%SubField{} = sf), do: sf |> parse_keys() |> parse_children()
  defp parse(%ConditionalField{} = cf), do: cf |> parse_keys() |> parse_children()
  defp parse(other), do: other

  defp parse_keys(entity) do
    %{
      entity
      | __from_path__: parse_path(entity.from),
        __on_path__: parse_path(entity.on),
        __domain_ops__: parse_domain(entity.domain)
    }
  end

  defp parse_children(entity) do
    %{
      entity
      | fields: Enum.map(entity.fields, &parse/1),
        sub_fields: Enum.map(entity.sub_fields, &parse/1),
        conditional_fields: Enum.map(entity.conditional_fields, &parse/1)
    }
  end

  defp parse_path(nil), do: nil
  defp parse_path(""), do: nil
  defp parse_path(str) when is_binary(str), do: Parser.parse_core_keys_pattern(str)
  defp parse_path(_), do: nil

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
    data |> String.split(",", trim: true) |> Enum.map_join("::", &String.trim/1)
  end

  # The domain string comes from the developer's DSL and is read at compile time, never
  # from user input.
  # sobelow_skip ["RCE.CodeModule"]
  defp eval_re_structure(data) do
    {converted, []} = Code.eval_string(data)
    Enum.map_join(converted, &"#{Macro.to_string(&1)}::")
  end
end
