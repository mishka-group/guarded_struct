defmodule GuardedStruct.Typedoc do
  @moduledoc false

  # The type of each field in the generated `@type t`, and the `@typedoc` of `t`: a Markdown
  # table of the fields.
  #
  # A field's declared type is kept when it already says something. When it is a loose one
  # (`struct()`, `map()`, `any()`, `term()`, `list()` or a list of those), the type comes
  # from what the field builds: `struct: Mod` is `Mod.t()`, `structs: Mod` is `[Mod.t()]`, a
  # sub_field is the `t()` of its module, and a conditional_field is the union of its
  # branches. The docs of `t()` then link each nested type to its own page.

  alias GuardedStruct.Dsl.{ConditionalField, Field, SubField, VirtualField}

  @loose [:struct, :map, :any, :term]

  @doc """
  The type of `entity` in `t()`, without the `| nil` of a field that is not enforced.
  `owner` is the alias AST of the module the entity belongs to; a sub_field's module is
  named under it.
  """
  def type_of(entity, owner \\ local_owner())

  def type_of(%ConditionalField{} = cf, owner) do
    if loose?(cf.type), do: conditional_type(cf, owner), else: cf.type
  end

  # A generated module with `doc: false` has no page, so the declared type stays: ExDoc warns
  # about a type in a spec that links to a hidden module.
  def type_of(%SubField{doc: false} = sf, owner) do
    if generates_module?(sf) or not loose?(sf.type),
      do: sf.type,
      else: built_type(sf, owner)
  end

  def type_of(%{type: type} = entity, owner) do
    if loose?(type), do: built_type(entity, owner) || type, else: type
  end

  def type_of(_entity, _owner), do: quote(do: any())

  # `__MODULE__`, the module whose body holds the type.
  defp local_owner, do: {:__aliases__, [alias: false], [{:__MODULE__, [], nil}]}

  defp built_type(entity, owner) do
    structs = Map.get(entity, :structs)
    struct = Map.get(entity, :struct)

    cond do
      is_atom(structs) and structs not in [nil, true, false] -> [remote_t(structs)]
      is_atom(struct) and not is_nil(struct) -> remote_t(struct)
      match?(%SubField{}, entity) -> sub_field_type(entity, entity.name, owner)
      true -> nil
    end
  end

  defp sub_field_type(%SubField{} = sf, module_name, owner) do
    type = remote_t(child_alias(owner, module_name))
    if sf.structs == true, do: [type], else: type
  end

  # The branches of a conditional_field in source order; a sub_field inside it is the
  # numbered module `<Name><index>`, as GenerateSubFieldModules names it.
  defp conditional_type(%ConditionalField{} = cf, owner) do
    {types, _index} =
      cf
      |> GuardedStruct.Transformers.Codegen.conditional_children()
      |> Enum.map_reduce(0, fn
        %SubField{} = sf, index ->
          numbered = :"#{cf.name}#{index + 1}"

          {built_type_numbered(sf, numbered, owner), index + 1}

        child, index ->
          {type_of(child, owner), index}
      end)

    union = types |> Enum.uniq_by(&Macro.to_string/1) |> union()
    if cf.structs == true, do: [union], else: union
  end

  defp built_type_numbered(%SubField{} = sf, numbered, owner),
    do: type_of(%{sf | name: numbered}, owner)

  defp union([single]), do: single
  defp union([head | rest]), do: {:|, [], [head, union(rest)]}

  defp child_alias({:__aliases__, meta, parts}, name),
    do: {:__aliases__, meta, parts ++ [GuardedStruct.Transformers.Codegen.atom_to_module(name)]}

  defp remote_t(module), do: {{:., [], [module, :t]}, [], []}

  @doc "True when a declared type says no more than \"some struct, map or list\"."
  def loose?({name, _, args}) when name in @loose and args in [nil, []], do: true
  def loose?({:list, _, args}) when args in [nil, []], do: true
  def loose?({:list, _, [inner]}), do: loose?(inner)
  def loose?([inner]), do: loose?(inner)
  def loose?({:|, _, [left, right]}), do: loose?(left) and loose?(right)
  def loose?(_type), do: false

  @doc """
  The rows of the field table, worked out at code generation. `render/2` turns them into
  Markdown once the module name is known.
  """
  def rows(entities, enforce_keys) do
    entities
    |> Enum.uniq_by(& &1.name)
    |> Enum.reject(&(Map.get(&1, :doc) == false and not match?(%SubField{}, &1)))
    |> Enum.map(fn entity ->
      required? = entity.name in enforce_keys
      type = type_of(entity)

      %{
        name: entity.name,
        kind: kind(entity),
        type: if(required?, do: type, else: {:|, [], [type, nil]}),
        required: required?,
        default: entity.default,
        derives: Map.get(entity, :derives) || Map.get(entity, :derive),
        validator: Map.get(entity, :validator),
        doc: row_doc(entity),
        links: links(entity)
      }
    end)
  end

  @doc "The rows of a pattern-keyed map: one per key pattern."
  def pattern_rows(entities) do
    Enum.map(entities, fn %Field{} = field ->
      %{
        name: pattern_source(field.name),
        kind: :pattern,
        type: type_of(field),
        required: false,
        default: field.default,
        derives: field.derives || field.derive,
        validator: field.validator,
        doc: row_doc(field),
        links: links(field)
      }
    end)
  end

  defp pattern_source({:regex_pattern, source}), do: source
  defp pattern_source(%Regex{source: source}), do: source

  defp kind(%VirtualField{}), do: :virtual
  defp kind(_entity), do: :field

  # A sub_field's doc is its module's @moduledoc; its first paragraph is the row text.
  defp row_doc(%{doc: doc}) when is_binary(doc) do
    doc |> String.trim() |> String.split(~r/\n\s*\n/, parts: 2) |> hd()
  end

  defp row_doc(_entity), do: nil

  # The modules the field builds, whose `t()` the table links to: a `struct:`/`structs:`
  # module, or `{:local, name}` for a sub_field's module under the owner. A generated module
  # with `doc: false` has no page, so it is not linked.
  defp links(%ConditionalField{} = cf) do
    {links, _index} =
      cf
      |> GuardedStruct.Transformers.Codegen.conditional_children()
      |> Enum.flat_map_reduce(0, fn
        %SubField{} = sf, index -> {links(%{sf | name: :"#{cf.name}#{index + 1}"}), index + 1}
        child, index -> {links(child), index}
      end)

    links
  end

  defp links(entity) do
    structs = Map.get(entity, :structs)
    struct = Map.get(entity, :struct)

    cond do
      is_atom(structs) and structs not in [nil, true, false] -> [structs]
      is_atom(struct) and not is_nil(struct) -> [struct]
      match?(%SubField{doc: false}, entity) and generates_module?(entity) -> []
      match?(%SubField{}, entity) -> [{:local, entity.name}]
      true -> []
    end
  end

  @doc "True when the sub_field has a `do` block, so a module is generated for it."
  def generates_module?(%SubField{} = sf),
    do: sf.fields != [] or sf.sub_fields != [] or sf.conditional_fields != []

  @doc """
  The Markdown of the `@typedoc` of `t()` in `module`. Called in the module body, where the
  module name is known.
  """
  # Description comes before the derives, whose long strings would push it out of view.
  def render(%Macro.Env{} = env, rows) do
    {fields, virtual} = Enum.split_with(rows, &(&1.kind != :virtual))
    pattern? = Enum.any?(fields, &(&1.kind == :pattern))

    intro =
      if pattern?,
        do: "The map that `builder/1` returns. Each key matches one of these patterns.",
        else: "The struct that `builder/1` returns."

    virtual_part =
      if virtual == [],
        do: [],
        else: [
          "Virtual fields: `builder/1` checks them and leaves them out of the struct.",
          table(env, virtual, "Field")
        ]

    field_part = if fields == [], do: [], else: [table(env, fields, header(pattern?))]

    Enum.join([intro | field_part ++ virtual_part], "\n\n") <> "\n"
  end

  defp header(true), do: "Key pattern"
  defp header(false), do: "Field"

  defp table(env, rows, name_header) do
    head = [
      "| #{name_header} | Type | Required | Default | Description | Derives |",
      "| --- | --- | --- | --- | --- | --- |"
    ]

    lines =
      Enum.map(rows, fn row ->
        cells = [
          code(name_cell(row)),
          type_cell(env, row),
          if(row.required, do: "yes", else: "no"),
          default_cell(row.default),
          text(row.doc),
          checks_cell(row)
        ]

        "| " <> Enum.join(cells, " | ") <> " |"
      end)

    Enum.join(head ++ lines, "\n")
  end

  defp name_cell(%{kind: :pattern, name: source}), do: "~r/#{source}/"
  defp name_cell(%{name: name}), do: inspect(name)

  defp default_cell(nil), do: ""
  defp default_cell(default), do: code(inspect(default))

  defp checks_cell(row) do
    derives = if row.derives, do: [code(row.derives)], else: []

    validator =
      case row.validator do
        {mod, fun} -> ["validator " <> code(inspect({mod, fun}))]
        _ -> []
      end

    Enum.join(derives ++ validator, "<br>")
  end

  # Each part of a union on its own; a `Mod.t()` or `[Mod.t()]` part whose module the field
  # builds links to that type.
  defp type_cell(env, row) do
    links =
      Enum.map(row.links, fn
        {:local, name} -> Module.concat(env.module, atom_to_module(name))
        module -> module
      end)

    row.type
    |> expand_aliases(env)
    |> union_parts()
    |> Enum.map_join(" \\| ", &type_part(&1, links))
  end

  defp type_part({{:., _, [module, :t]}, _, []} = part, links),
    do: linked(part, module, links)

  defp type_part([{{:., _, [module, :t]}, _, []}] = part, links),
    do: linked(part, module, links)

  defp type_part(part, _links), do: code(Macro.to_string(part))

  defp linked(part, module, links) do
    shown = code(Macro.to_string(part))
    if module in links, do: "[#{shown}](`t:#{inspect(module)}.t/0`)", else: shown
  end

  defp union_parts({:|, _, [left, right]}), do: union_parts(left) ++ union_parts(right)
  defp union_parts(part), do: [part]

  # Aliases in the types, `__MODULE__.Child` included, become full module names.
  defp expand_aliases(type, env) do
    Macro.prewalk(type, fn
      {:__aliases__, _, _} = alias_ast -> Macro.expand(alias_ast, env)
      other -> other
    end)
  end

  defp atom_to_module(name), do: GuardedStruct.Transformers.Codegen.atom_to_module(name)

  # Inline code with the table's column separator escaped.
  defp code(text), do: "`" <> escape(text) <> "`"

  defp text(nil), do: ""
  defp text(doc), do: doc |> String.replace(~r/\s*\n\s*/, " ") |> escape()

  defp escape(text), do: String.replace(text, "|", "\\|")
end
