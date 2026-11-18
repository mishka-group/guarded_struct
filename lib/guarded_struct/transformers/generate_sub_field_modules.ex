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

    json? = Transformer.get_option(dsl_state, [:guardedstruct], :json) == true

    inherited = %{
      json: json?,
      validate_derive: Transformer.get_option(dsl_state, [:guardedstruct], :validate_derive),
      sanitize_derive: Transformer.get_option(dsl_state, [:guardedstruct], :sanitize_derive)
    }

    # Walk the entity tree and submit each Module.create as an async
    # compile task on the dsl_state. Spark awaits all tasks before the
    # next transformer (GenerateBuilder) runs, so sibling submodules
    # compile in parallel while preserving the parent → builder order.
    dsl_state = generate_for_entities(entities, [base_module], inherited, dsl_state)

    {:ok, dsl_state}
  end

  defp resolve_module_ast(parent, {:__aliases__, _, parts}) when is_list(parts) do
    Module.concat([parent | parts])
  end

  defp resolve_module_ast(parent, name) when is_atom(name), do: Module.concat(parent, name)

  defp generate_for_entities(entities, parent_path, inherited, dsl_state) do
    Enum.reduce(entities, dsl_state, fn
      %SubField{} = sf, acc ->
        generate_sub_field(sf, parent_path, inherited, acc)

      %ConditionalField{} = cf, acc ->
        acc =
          cf.sub_fields
          |> Enum.with_index(1)
          |> Enum.reduce(acc, fn {inner_sf, idx}, inner_acc ->
            numbered_name = "#{cf.name}#{idx}" |> String.to_atom()
            renamed = %{inner_sf | name: numbered_name}
            generate_sub_field(renamed, parent_path, inherited, inner_acc)
          end)

        Enum.reduce(cf.conditional_fields, acc, fn inner_cf, inner_acc ->
          generate_for_entities([inner_cf], parent_path, inherited, inner_acc)
        end)

      _, acc ->
        acc
    end)
  end

  defp generate_sub_field(%SubField{} = sf, parent_path, inherited, dsl_state) do
    submodule = Module.concat(parent_path ++ [Codegen.atom_to_module(sf.name)])

    if GuardedStruct.Typedoc.generates_module?(sf) do
      generate_module(sf, submodule, parent_path, inherited, dsl_state)
    else
      use_own_module!(sf, submodule, dsl_state)
      dsl_state
    end
  end

  # A sub_field without a `do` block uses the user's own module of the generated name, like
  # `field name, struct(), struct: Module`. Its options that shape a generated module would
  # be ignored, so they are refused.
  defp use_own_module!(%SubField{} = sf, submodule, dsl_state) do
    shaping =
      Enum.filter([:authorized_fields, :main_validator, :error], &(Map.get(sf, &1) != nil))

    cond do
      shaping != [] ->
        raise_dsl!(dsl_state, sf.name, own_module_options_message(submodule, sf.name, shaping))

      not own_module?(submodule, dsl_state) ->
        raise_dsl!(dsl_state, sf.name, missing_module_message(submodule, sf.name))

      true ->
        :ok
    end
  end

  # A module nested in the parent is already compiled, and the env lists it. For any other,
  # `Code.ensure_compiled/1` makes the compiler wait for the file that defines it.
  defp own_module?(submodule, dsl_state) do
    nested = dsl_state |> Transformer.get_persisted(:env) |> context_modules()

    submodule in nested or
      (match?({:module, _}, Code.ensure_compiled(submodule)) and
         function_exported?(submodule, :builder, 1))
  end

  defp raise_dsl!(dsl_state, name, message) do
    raise Spark.Error.DslError,
      module: Transformer.get_persisted(dsl_state, :module),
      path: [:guardedstruct, :sub_field, name],
      message: message
  end

  @doc false
  def missing_module_message(submodule, name) do
    "sub_field #{inspect(name)} has no do block, so it uses the module #{inspect(submodule)}, " <>
      "but there is no such module with a builder/1. Define #{inspect(submodule)} " <>
      "(for example with use GuardedStruct), or give the sub_field a do block with its fields."
  end

  defp own_module_options_message(submodule, name, options) do
    "sub_field #{inspect(name)} has no do block, so it uses your module " <>
      "#{inspect(submodule)} as it is, and #{Enum.map_join(options, ", ", &inspect/1)} " <>
      "would be ignored. Set them in the guardedstruct of #{inspect(submodule)}."
  end

  defp generate_module(%SubField{} = sf, submodule, parent_path, inherited, dsl_state) do
    new_path = parent_path ++ [Codegen.atom_to_module(sf.name)]

    # Recurse first so child submodule tasks are registered on dsl_state
    # before the parent's own task is added. Order of task creation is
    # cosmetic only (Spark awaits all of them); the parent's compiled
    # output doesn't reference children at compile time.
    dsl_state =
      generate_for_entities(
        sf.sub_fields ++ sf.conditional_fields,
        new_path,
        inherited,
        dsl_state
      )

    Codegen.validate_entities!(sf.fields ++ sf.sub_fields ++ sf.conditional_fields)

    body =
      Codegen.build_body(
        sf.fields ++ sf.sub_fields ++ sf.conditional_fields,
        sf.enforce == true,
        false,
        sf.error == true,
        info_path(submodule),
        Map.merge(inherited, %{
          authorized_fields: sf.authorized_fields == true,
          main_validator: sf.main_validator
        })
      )

    body = with_moduledoc(body, sf.doc)
    file = file_for(sf)
    line = line_for(sf)

    refuse_taken_name!(submodule, sf.name, dsl_state)

    dsl_state
    |> remember_generated(submodule, sf.name)
    |> Transformer.async_compile(fn ->
      Module.create(submodule, body, file: file, line: line)
    end)
  end

  # Raises when the generated name belongs to another module, so the generated module does
  # not silently replace the user's own one: a module nested in the parent (the compiler
  # loads those lazily, so only the env lists them) or one already loaded.
  defp refuse_taken_name!(submodule, name, dsl_state) do
    nested = dsl_state |> Transformer.get_persisted(:env) |> context_modules()

    if submodule in nested or
         (Code.ensure_loaded?(submodule) and not generated_sub_field?(submodule)) do
      raise Spark.Error.DslError,
        module: Transformer.get_persisted(dsl_state, :module),
        path: [:guardedstruct, :sub_field, name],
        message: taken_name_message(submodule, name)
    end
  end

  defp context_modules(%Macro.Env{context_modules: modules}), do: modules
  defp context_modules(_), do: []

  @doc false
  # True when `module` is a module a sub_field generated (its info key is not `:root`).
  def generated_sub_field?(module) do
    function_exported?(module, :__guarded_information__, 0) and
      module.__guarded_information__().key != :root
  end

  @doc false
  # The error shown when the module name a sub_field generates belongs to another module.
  def taken_name_message(submodule, name) do
    "sub_field #{inspect(name)} generates the module #{inspect(submodule)}, but another " <>
      "module with that name is defined. Rename the sub_field, or drop its do block to use " <>
      "your module as it is: sub_field #{inspect(name)}, struct()"
  end

  # Persists each generated module with its sub_field name for the post-compile check.
  defp remember_generated(dsl_state, submodule, name) do
    generated = Transformer.get_persisted(dsl_state, :guarded_sub_field_modules, [])
    Transformer.persist(dsl_state, :guarded_sub_field_modules, [{submodule, name} | generated])
  end

  # The `doc:` option is the generated module's @moduledoc; without it the module has none.
  defp with_moduledoc(body, nil), do: body

  defp with_moduledoc(body, doc) do
    quote do
      @moduledoc unquote(doc)
      unquote(body)
    end
  end

  defp info_path(submodule), do: Module.split(submodule) |> Enum.map(&String.to_atom/1)

  defp file_for(%{__spark_metadata__: %{anno: anno}}) when is_map(anno),
    do: Map.get(anno, :file, "nofile")

  defp file_for(_), do: "nofile"

  defp line_for(%{__spark_metadata__: %{anno: anno}}) when is_map(anno),
    do: Map.get(anno, :line, 1)

  defp line_for(_), do: 1
end
