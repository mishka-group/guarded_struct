defmodule GuardedStruct.Transformers.GenerateSubFieldModules do
  @moduledoc false

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer
  alias GuardedStruct.Dsl.{SubField, ConditionalField}
  alias GuardedStruct.Transformers.Codegen

  @impl true
  def before?(GuardedStruct.Transformers.GenerateBuilder), do: true
  def before?(_), do: false

  @impl true
  def transform(dsl_state) do
    parent = Transformer.get_persisted(dsl_state, :module)
    module_opt = Transformer.get_option(dsl_state, [:guardedstruct], :module)
    entities = Transformer.get_entities(dsl_state, [:guardedstruct])

    base_module =
      case module_opt do
        nil -> parent
        ast -> resolve_module_ast(parent, ast)
      end

    generate_for_entities(entities, [base_module])

    {:ok, dsl_state}
  end

  defp resolve_module_ast(parent, {:__aliases__, _, parts}) when is_list(parts) do
    Module.concat([parent | parts])
  end

  defp resolve_module_ast(parent, name) when is_atom(name), do: Module.concat(parent, name)
  defp resolve_module_ast(_parent, mod) when is_atom(mod), do: mod

  defp generate_for_entities(entities, parent_path) do
    Enum.each(entities, fn
      %SubField{} = sf ->
        generate_sub_field(sf, parent_path)

      %ConditionalField{} = cf ->
        cf.sub_fields
        |> Enum.with_index(1)
        |> Enum.each(fn {inner_sf, idx} ->
          numbered_name = "#{cf.name}#{idx}" |> String.to_atom()
          renamed = %{inner_sf | name: numbered_name}
          generate_sub_field(renamed, parent_path)
        end)

        Enum.each(cf.conditional_fields, fn inner_cf ->
          generate_for_entities([inner_cf], parent_path)
        end)

      _ ->
        :ok
    end)
  end

  defp generate_sub_field(%SubField{} = sf, parent_path) do
    submodule = Module.concat(parent_path ++ [Codegen.atom_to_module(sf.name)])

    new_path = parent_path ++ [Codegen.atom_to_module(sf.name)]

    # Recurse for nested sub_fields and conditional_fields inside this one.
    generate_for_entities(sf.sub_fields ++ sf.conditional_fields, new_path)

    Codegen.validate_entities!(sf.fields ++ sf.sub_fields ++ sf.conditional_fields)

    body =
      Codegen.build_body(
        sf.fields ++ sf.sub_fields ++ sf.conditional_fields,
        sf.enforce == true,
        false,
        sf.error == true,
        info_path(submodule),
        %{authorized_fields: sf.authorized_fields == true}
      )

    Module.create(submodule, body, file: file_for(sf), line: line_for(sf))
  end

  defp info_path(submodule), do: Module.split(submodule) |> Enum.map(&String.to_atom/1)

  defp file_for(%{__spark_metadata__: %{anno: anno}}) when is_map(anno),
    do: Map.get(anno, :file, "nofile")

  defp file_for(_), do: "nofile"

  defp line_for(%{__spark_metadata__: %{anno: anno}}) when is_map(anno),
    do: Map.get(anno, :line, 1)

  defp line_for(_), do: 1
end
