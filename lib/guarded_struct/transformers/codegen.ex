defmodule GuardedStruct.Transformers.Codegen do
  @moduledoc false

  # Shared code-generation helpers. Used by:
  #   * GenerateBuilder — top-level user module (full struct + builder/2)
  #   * GenerateSubFieldModules — per-sub_field nested submodules
  #   * GenerateAshValidator — Ash resource extension variant (no struct,
  #     no builder/2; emits __guarded_validate__/1 instead)
  #
  # `build_body/6` accepts a `variant:` option to switch between the
  # full struct+builder body and the Ash-friendly validator-only body.

  alias GuardedStruct.Dsl.{Field, SubField, ConditionalField}

  @doc """
  Public entry point — also used by the Ash extension's transformer.
  """
  def struct_pieces(entities, block_enforce), do: build_struct_pieces(entities, block_enforce)

  @doc """
  Build the codegen body for a guardedstruct module.

  * `entities` — list of `%Field{}` and `%SubField{}` (and later
    `%ConditionalField{}`) entities collected from DSL state.
  * `block_enforce` — section-level `enforce: true` flag.
  * `opaque?` — section-level `opaque: true` flag.
  * `error?` — section-level `error: true` flag (generates an `Error` exception).
  * `path` — for nested submodules, the list of atoms representing the path from
    the root user module down to this submodule (used in `__information__/0`).
  """
  def build_body(entities, block_enforce, opaque?, error?, path \\ [], options \\ %{}) do
    {keys, defstruct_kw, types, enforce_keys, fields_runtime} =
      build_struct_pieces(entities, block_enforce)

    info_map =
      Macro.escape(%{
        path: path,
        key: if(path == [], do: :root, else: List.last(path)),
        keys: keys,
        enforce_keys: enforce_keys,
        conditional_keys: [],
        options: options
      })

    quote do
      @enforce_keys unquote(enforce_keys)
      defstruct unquote(defstruct_kw)

      if unquote(opaque?) do
        @opaque t() :: %__MODULE__{unquote_splicing(types)}
      else
        @type t() :: %__MODULE__{unquote_splicing(types)}
      end

      # If the user redefined any of these in their module body, mark theirs
      # overridable so our generated bodies (which know the actual values) win.
      if Module.defines?(__MODULE__, {:keys, 0}, :def),
        do: defoverridable(keys: 0)

      if Module.defines?(__MODULE__, {:keys, 1}, :def),
        do: defoverridable(keys: 1)

      if Module.defines?(__MODULE__, {:enforce_keys, 0}, :def),
        do: defoverridable(enforce_keys: 0)

      if Module.defines?(__MODULE__, {:enforce_keys, 1}, :def),
        do: defoverridable(enforce_keys: 1)

      if Module.defines?(__MODULE__, {:__information__, 0}, :def),
        do: defoverridable(__information__: 0)

      if Module.defines?(__MODULE__, {:__fields__, 0}, :def),
        do: defoverridable(__fields__: 0)

      if Module.defines?(__MODULE__, {:builder, 1}, :def),
        do: defoverridable(builder: 1)

      if Module.defines?(__MODULE__, {:builder, 2}, :def),
        do: defoverridable(builder: 2)

      def keys, do: unquote(keys)
      def keys(:all), do: GuardedStruct.Runtime.all_keys(__MODULE__)
      def keys(field) when is_atom(field), do: field in unquote(keys)

      def enforce_keys, do: unquote(enforce_keys)
      def enforce_keys(:all), do: GuardedStruct.Runtime.all_enforce_keys(__MODULE__)
      def enforce_keys(field) when is_atom(field), do: field in unquote(enforce_keys)

      def __information__ do
        Map.put(unquote(info_map), :module, __MODULE__)
      end

      def __fields__, do: unquote(Macro.escape(fields_runtime))

      # Header: defines the default for the trailing arg. All clauses below
      # share this default (Elixir requires a header when a multi-clause def
      # sets a default).
      def builder(attrs_or_input, error \\ false)

      def builder({_, _} = input, error),
        do: GuardedStruct.Runtime.build(__MODULE__, input, error)

      def builder({_, _, _} = input, error),
        do: GuardedStruct.Runtime.build(__MODULE__, input, error)

      def builder(attrs, error),
        do: GuardedStruct.Runtime.build(__MODULE__, attrs, error)

      if unquote(error?) do
        defmodule Error do
          defexception [:errors, :term]

          @impl true
          def message(%{errors: errs, term: term}) do
            "There is at least one validation problem with your data: #{inspect(term)}\n" <>
              "Errors: #{inspect(errs)}"
          end
        end
      end
    end
  end

  @doc """
  Validate field-level invariants and raise legacy-compatible `ArgumentError`s
  for two cases the existing test suite relies on:

  * non-atom `field` names → `"a field name must be an atom, got X"`
  * duplicate field names at the same scope → `"the field :name is already set"`
  """
  def validate_entities!(entities) do
    Enum.reduce(entities, [], fn entity, seen ->
      name = entity_name(entity)

      cond do
        is_atom(name) and not is_nil(name) ->
          if name in seen do
            raise ArgumentError, "the field #{inspect(name)} is already set"
          end

          [name | seen]

        is_number(name) or is_binary(name) ->
          raise ArgumentError, "a field name must be an atom, got #{inspect(name)}"

        true ->
          seen
      end
    end)

    :ok
  end

  defp entity_name(%Field{name: n}), do: n
  defp entity_name(%SubField{name: n}), do: n
  defp entity_name(other), do: Map.get(other, :name)

  defp build_struct_pieces(entities, block_enforce) do
    # A ConditionalField at the same scope can have multiple children with
    # the same `:name` — but the parent struct only needs ONE field per name.
    # Keep the unique names while preserving declaration order.
    unique_entities =
      Enum.uniq_by(entities, & &1.name)

    keys = Enum.map(unique_entities, & &1.name)

    defstruct_kw =
      Enum.map(unique_entities, fn
        %Field{} = f -> {f.name, f.default}
        %SubField{} = sf -> {sf.name, sf.default}
        %ConditionalField{} = cf -> {cf.name, cf.default}
        other -> {other.name, nil}
      end)

    enforce_keys =
      Enum.flat_map(unique_entities, fn
        %Field{} = f ->
          enforce_for_field(f, block_enforce)

        %SubField{} = sf ->
          enforce_for_field(sf, block_enforce)

        %ConditionalField{} = cf ->
          if cf.enforce == true, do: [cf.name], else: []

        other ->
          if Map.get(other, :enforce) == true, do: [other.name], else: []
      end)
      |> Enum.reverse()

    types =
      Enum.map(unique_entities, fn entity ->
        nullable? = entity.name not in enforce_keys

        type_ast =
          case entity do
            %Field{type: t} -> t
            %SubField{type: t} -> t
            %ConditionalField{type: t} -> t
            other -> Map.get(other, :type)
          end

        {entity.name, if(nullable?, do: nullable_type(type_ast), else: type_ast)}
      end)

    # `fields_runtime` keeps ALL entities (including duplicates from a
    # conditional_field's children at the same name) — runtime needs every
    # candidate to do conditional dispatch. The struct-level pieces above
    # were de-duped because the struct only has one slot per name.
    fields_runtime =
      Enum.map(entities, fn
        %Field{} = f ->
          %{
            kind: :field,
            name: f.name,
            derive: f.derive,
            validator: f.validator,
            auto: f.auto,
            on: f.on,
            from: f.from,
            domain: f.domain,
            struct: f.struct,
            structs: f.structs,
            hint: f.hint,
            priority: f.priority,
            default: f.default
          }

        %SubField{} = sf ->
          %{
            kind: :sub_field,
            name: sf.name,
            derive: sf.derive,
            validator: sf.validator,
            auto: sf.auto,
            on: sf.on,
            from: sf.from,
            domain: sf.domain,
            struct: sf.struct,
            structs: sf.structs,
            hint: sf.hint,
            priority: sf.priority,
            default: sf.default,
            error: sf.error,
            authorized_fields: sf.authorized_fields,
            main_validator: sf.main_validator,
            list?: sf.structs == true
          }

        %ConditionalField{} = cf ->
          %{
            kind: :conditional_field,
            name: cf.name,
            derive: cf.derive,
            validator: cf.validator,
            auto: cf.auto,
            on: cf.on,
            from: cf.from,
            domain: cf.domain,
            struct: cf.struct,
            structs: cf.structs,
            hint: cf.hint,
            priority: cf.priority,
            default: cf.default,
            list?: cf.structs == true,
            children: encode_children(merge_children_in_source_order(cf))
          }

        other ->
          %{kind: :unknown, name: other.name}
      end)

    {keys, defstruct_kw, types, enforce_keys, fields_runtime}
  end

  # Spark partitions a conditional_field's children into separate `:fields`,
  # `:sub_fields`, and `:conditional_fields` lists, losing source-declaration
  # order. Existing tests pattern-match on the original declared order, so we
  # use `__spark_metadata__.anno.line` to recover it.
  defp merge_children_in_source_order(%ConditionalField{} = cf) do
    (cf.fields ++ cf.sub_fields ++ cf.conditional_fields)
    |> Enum.sort_by(&entity_line/1)
  end

  # `__spark_metadata__.anno` is `nil` when this code runs (in a transformer),
  # but the field's `:type` AST carries `[line: N, column: N]` metadata from
  # parsing — that's what we use to recover declaration order.
  defp entity_line(%{type: type_ast}) do
    extract_line(type_ast)
  end

  defp entity_line(_), do: 0

  defp extract_line({_, meta, _}) when is_list(meta), do: Keyword.get(meta, :line, 0)
  defp extract_line({_, meta, _, _}) when is_list(meta), do: Keyword.get(meta, :line, 0)
  defp extract_line(_), do: 0

  defp encode_children(entities) do
    # Number sub_fields by encounter order so the runtime knows which
    # auto-generated submodule (e.g. `Thing1`, `Thing2`) corresponds to which
    # child. Plain fields and conditional_fields don't carry an index.
    {result, _} =
      Enum.reduce(entities, {[], 0}, fn
        %Field{} = f, {acc, sf_count} ->
          encoded = %{
            kind: :field,
            name: f.name,
            derive: f.derive,
            validator: f.validator,
            struct: f.struct,
            structs: f.structs,
            hint: f.hint
          }

          {acc ++ [encoded], sf_count}

        %SubField{} = sf, {acc, sf_count} ->
          new_count = sf_count + 1

          encoded = %{
            kind: :sub_field,
            name: sf.name,
            sub_field_index: new_count,
            derive: sf.derive,
            validator: sf.validator,
            structs: sf.structs,
            hint: sf.hint,
            list?: sf.structs == true
          }

          {acc ++ [encoded], new_count}

        %ConditionalField{} = cf, {acc, sf_count} ->
          encoded = %{
            kind: :conditional_field,
            name: cf.name,
            derive: cf.derive,
            validator: cf.validator,
            hint: cf.hint,
            # `structs: true` on a nested conditional means "list-of-this-shape"
            # — the runtime needs this to iterate per-element. Without these
            # the inner-conditional list mode silently broke (see test
            # "nested conditional resolves a list → INNER conditional with
            # list children" in nested_conditional_field_test.exs).
            structs: cf.structs,
            list?: cf.structs == true,
            children: encode_children(merge_children_in_source_order(cf))
          }

          {acc ++ [encoded], sf_count}
      end)

    result
  end

  defp enforce_for_field(field, block_enforce) do
    cond do
      field.enforce == false -> []
      field.enforce == true -> [field.name]
      block_enforce and is_nil(field.default) -> [field.name]
      true -> []
    end
  end

  defp nullable_type(type_ast), do: {:|, [], [type_ast, nil]}

  @doc """
  Camelize an atom field name into a submodule name component.

      iex> GuardedStruct.Transformers.Codegen.atom_to_module(:my_field)
      :MyField
  """
  def atom_to_module(field_atom) do
    field_atom |> Atom.to_string() |> Macro.camelize() |> String.to_atom()
  end
end
