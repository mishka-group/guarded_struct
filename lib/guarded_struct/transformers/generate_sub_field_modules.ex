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

    jason? = Transformer.get_option(dsl_state, [:guardedstruct], :jason) == true

    # Walk the entity tree and submit each Module.create as an async
    # compile task on the dsl_state. Spark awaits all tasks before the
    # next transformer (GenerateBuilder) runs, so sibling submodules
    # compile in parallel while preserving the parent → builder order.
    dsl_state = generate_for_entities(entities, [base_module], jason?, dsl_state)

    {:ok, dsl_state}
  end

  defp resolve_module_ast(parent, {:__aliases__, _, parts}) when is_list(parts) do
    Module.concat([parent | parts])
  end

  defp resolve_module_ast(parent, name) when is_atom(name), do: Module.concat(parent, name)
  defp resolve_module_ast(_parent, mod) when is_atom(mod), do: mod

  defp generate_for_entities(entities, parent_path, jason?, dsl_state) do
    Enum.reduce(entities, dsl_state, fn
      %SubField{} = sf, acc ->
        generate_sub_field(sf, parent_path, jason?, acc)

      %ConditionalField{} = cf, acc ->
        acc =
          cf.sub_fields
          |> Enum.with_index(1)
          |> Enum.reduce(acc, fn {inner_sf, idx}, inner_acc ->
            numbered_name = "#{cf.name}#{idx}" |> String.to_atom()
            renamed = %{inner_sf | name: numbered_name}
            generate_sub_field(renamed, parent_path, jason?, inner_acc)
          end)

        Enum.reduce(cf.conditional_fields, acc, fn inner_cf, inner_acc ->
          generate_for_entities([inner_cf], parent_path, jason?, inner_acc)
        end)

      _, acc ->
        acc
    end)
  end

  defp generate_sub_field(%SubField{} = sf, parent_path, jason?, dsl_state) do
    submodule = Module.concat(parent_path ++ [Codegen.atom_to_module(sf.name)])
    new_path = parent_path ++ [Codegen.atom_to_module(sf.name)]

    # Recurse first so child submodule tasks are registered on dsl_state
    # before the parent's own task is added. Order of task creation is
    # cosmetic only (Spark awaits all of them); the parent's compiled
    # output doesn't reference children at compile time.
    dsl_state =
      generate_for_entities(sf.sub_fields ++ sf.conditional_fields, new_path, jason?, dsl_state)

    Codegen.validate_entities!(sf.fields ++ sf.sub_fields ++ sf.conditional_fields)

    body =
      Codegen.build_body(
        sf.fields ++ sf.sub_fields ++ sf.conditional_fields,
        sf.enforce == true,
        false,
        sf.error == true,
        info_path(submodule),
        %{authorized_fields: sf.authorized_fields == true, jason: jason?}
      )

    file = file_for(sf)
    line = line_for(sf)

    Transformer.async_compile(dsl_state, fn ->
      Module.create(submodule, body, file: file, line: line)
    end)
  end

  defp info_path(submodule), do: Module.split(submodule) |> Enum.map(&String.to_atom/1)

  defp file_for(%{__spark_metadata__: %{anno: anno}}) when is_map(anno),
    do: Map.get(anno, :file, "nofile")

  defp file_for(_), do: "nofile"

  defp line_for(%{__spark_metadata__: %{anno: anno}}) when is_map(anno),
    do: Map.get(anno, :line, 1)

  defp line_for(_), do: 1
end
