defmodule GuardedStruct.Transformers.Codegen do
  @moduledoc false

  alias GuardedStruct.Dsl.{Field, SubField, ConditionalField, VirtualField}

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
    case classify_shape(entities) do
      :pattern_map ->
        build_pattern_map_body(entities, error?, path, options)

      :struct ->
        build_struct_body(entities, block_enforce, opaque?, error?, path, options)

      {:mixed, atom_names, regex_names} ->
        raise Spark.Error.DslError,
          message:
            "cannot mix atom-keyed and regex-keyed `field` declarations in the same " <>
              "guardedstruct.\n" <>
              "Atom fields create fixed slots on a struct (#{inspect(atom_names)}); " <>
              "regex fields create entries in a free-form map " <>
              "(#{inspect(Enum.map(regex_names, &Regex.source/1))}).\n" <>
              "These shapes can't both fit in one Elixir struct. Either keep just one " <>
              "shape, or extract the regex part into a separate module and reference it " <>
              "via `struct:`.",
          path: [:guardedstruct]
    end
  end

  defp classify_shape(entities) do
    {atoms, regexes} =
      Enum.reduce(entities, {[], []}, fn entity, {a, r} ->
        case entity_name(entity) do
          name when is_atom(name) and not is_nil(name) -> {[name | a], r}
          %Regex{} = pattern -> {a, [pattern | r]}
          _ -> {a, r}
        end
      end)

    cond do
      atoms == [] and regexes != [] -> :pattern_map
      atoms != [] and regexes != [] -> {:mixed, Enum.reverse(atoms), Enum.reverse(regexes)}
      true -> :struct
    end
  end

  defp build_struct_body(entities, block_enforce, opaque?, error?, path, options) do
    {keys, defstruct_kw, types, enforce_keys, fields_runtime} =
      build_struct_pieces(entities, block_enforce)

    json? = Map.get(options, :json, false) == true

    # `json: true` opts into JSON encoding. Precedence:
    #   1. Jason.Encoder  — if user has `:jason` in their deps
    #   2. JSON.Encoder   — built-in on Elixir 1.18+
    #   3. no-op          — neither available
    derive_json_ast =
      if json? do
        quote do
          cond do
            Code.ensure_loaded?(Jason.Encoder) -> @derive Jason.Encoder
            Code.ensure_loaded?(JSON.Encoder) -> @derive JSON.Encoder
            true -> :ok
          end
        end
      end

    example_pairs =
      entities
      |> Enum.reject(&match?(%VirtualField{}, &1))
      |> Enum.uniq_by(& &1.name)
      |> Enum.map(fn entity -> {entity.name, example_value_ast(entity, path)} end)

    conditional_keys =
      entities
      |> Enum.filter(&match?(%ConditionalField{}, &1))
      |> Enum.map(& &1.name)
      |> Enum.uniq()

    virtual_keys =
      fields_runtime |> Enum.filter(&(&1.kind == :virtual_field)) |> Enum.map(& &1.name)

    dynamic_keys =
      fields_runtime |> Enum.filter(&(&1.kind == :dynamic_field)) |> Enum.map(& &1.name)

    info_map =
      Macro.escape(%{
        path: path,
        key: if(path == [], do: :root, else: List.last(path)),
        keys: keys,
        enforce_keys: enforce_keys,
        conditional_keys: conditional_keys,
        virtual_keys: virtual_keys,
        dynamic_keys: dynamic_keys,
        options: options
      })

    quote do
      unquote(derive_json_ast)
      @enforce_keys unquote(enforce_keys)
      defstruct unquote(escape_runtime(defstruct_kw))

      if unquote(opaque?) do
        @opaque t() :: %__MODULE__{unquote_splicing(types)}
      else
        @type t() :: %__MODULE__{unquote_splicing(types)}
      end

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

      @__guarded_fields__ GuardedStruct.Transformers.Codegen.bake_child_modules(
                            unquote(escape_runtime(fields_runtime)),
                            __MODULE__
                          )
      def __fields__, do: @__guarded_fields__

      @__guarded_field_meta_map__ Map.new(@__guarded_fields__, fn m -> {m.name, m} end)
      def __field_meta__(name), do: Map.get(@__guarded_field_meta_map__, name)

      def __guarded_information__, do: __information__()
      def __guarded_fields__, do: __fields__()
      def __guarded_field_meta__(name), do: __field_meta__(name)
      def __guarded_atom_lookup__, do: unquote(Macro.escape(atom_lookup_for(keys)))

      @__guarded_has_validator__ Module.defines?(__MODULE__, {:validator, 2}, :def)
      def __guarded_has_validator__, do: @__guarded_has_validator__

      @__guarded_has_main_validator__ Module.defines?(__MODULE__, {:main_validator, 1}, :def)
      def __guarded_has_main_validator__, do: @__guarded_has_main_validator__

      unless Module.defines?(__MODULE__, {:__guarded_derive_extensions_opt__, 0}, :def) do
        def __guarded_derive_extensions_opt__, do: nil
      end

      def builder(attrs_or_input, error \\ false)

      def builder({_, _} = input, error),
        do: GuardedStruct.Runtime.build(__MODULE__, input, error)

      def builder({_, _, _} = input, error),
        do: GuardedStruct.Runtime.build(__MODULE__, input, error)

      def builder(attrs, error),
        do: GuardedStruct.Runtime.build(__MODULE__, attrs, error)

      @doc "A sample %#{inspect(__MODULE__)}{} populated from defaults + type-based fallbacks."
      def example, do: struct(__MODULE__, unquote(example_pairs))

      if unquote(error?) do
        defmodule Error do
          defexception [:errors, :term]

          @impl true
          def message(%{errors: errs, term: term}) do
            """
            #{GuardedStruct.Messages.translated_message(:message_exception)}
             Term: #{inspect(term)}
             Errors: #{inspect(errs)}
            """
          end
        end

        def __guarded_error_module__, do: __MODULE__.Error
      else
        def __guarded_error_module__, do: nil
      end
    end
  end

  defp build_pattern_map_body(entities, error?, _path, options) do
    patterns = Enum.map(entities, & &1.name)

    fields_runtime =
      Enum.map(entities, fn %Field{} = f ->
        %{
          kind: :pattern_field,
          pattern: f.name,
          type: Macro.to_string(f.type),
          enforce: f.enforce,
          derive: f.derives || f.derive,
          __derive_ops__: f.__derive_ops__,
          validator: f.validator,
          struct: f.struct,
          structs: f.structs,
          hint: f.hint,
          default: f.default
        }
      end)

    info_map =
      Macro.escape(%{
        path: [],
        key: :pattern,
        keys: [],
        enforce_keys: [],
        conditional_keys: [],
        patterns: patterns,
        options: options,
        shape: :pattern_map
      })

    quote do
      def keys, do: []
      def keys(_), do: false
      def enforce_keys, do: []
      def enforce_keys(_), do: false

      def __information__ do
        Map.put(unquote(info_map), :module, __MODULE__)
      end

      def __fields__, do: unquote(escape_runtime(fields_runtime))

      def __field_meta__(_), do: nil

      def __guarded_information__, do: __information__()
      def __guarded_fields__, do: __fields__()
      def __guarded_field_meta__(_), do: nil
      def __guarded_atom_lookup__, do: %{}

      @__guarded_has_validator__ Module.defines?(__MODULE__, {:validator, 2}, :def)
      def __guarded_has_validator__, do: @__guarded_has_validator__

      @__guarded_has_main_validator__ Module.defines?(__MODULE__, {:main_validator, 1}, :def)
      def __guarded_has_main_validator__, do: @__guarded_has_main_validator__

      unless Module.defines?(__MODULE__, {:__guarded_derive_extensions_opt__, 0}, :def) do
        def __guarded_derive_extensions_opt__, do: nil
      end

      def example, do: %{}

      def builder(attrs, error \\ false)

      def builder({:__nested__, local_attrs, _full_attrs, _path, _type}, error),
        do: GuardedStruct.Runtime.build_pattern_map(__MODULE__, local_attrs, error)

      def builder({_, _} = input, error),
        do: GuardedStruct.Runtime.build_pattern_map(__MODULE__, input, error)

      def builder({_, _, _} = input, error),
        do: GuardedStruct.Runtime.build_pattern_map(__MODULE__, input, error)

      def builder(attrs, error),
        do: GuardedStruct.Runtime.build_pattern_map(__MODULE__, attrs, error)

      if unquote(error?) do
        defmodule Error do
          defexception [:errors, :term]

          @impl true
          def message(%{errors: errs, term: term}) do
            """
            #{GuardedStruct.Messages.translated_message(:message_exception)}
             Term: #{inspect(term)}
             Errors: #{inspect(errs)}
            """
          end
        end

        def __guarded_error_module__, do: __MODULE__.Error
      else
        def __guarded_error_module__, do: nil
      end
    end
  end

  @doc """
  Raise `ArgumentError` for non-atom non-regex field names or duplicate names.
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

        is_struct(name, Regex) ->
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

  defp atom_lookup_for(keys) when is_list(keys) do
    for k <- keys, is_atom(k), into: %{}, do: {Atom.to_string(k), k}
  end

  @doc """
  Inject `:child_module` into every `:sub_field` entry of the fields list.
  Called at parent module compile time so the value is
  `Module.concat(parent, ChildPart)` baked in — runtime never recomputes it.
  """
  def bake_child_modules(fields, parent_module) when is_list(fields) do
    Enum.map(fields, fn
      %{kind: :sub_field, name: name} = meta ->
        Map.put(meta, :child_module, Module.concat(parent_module, atom_to_module(name)))

      meta ->
        meta
    end)
  end

  defp build_struct_pieces(entities, block_enforce) do
    {virtual_entities, struct_entities} =
      Enum.split_with(entities, &match?(%VirtualField{}, &1))

    unique_entities =
      Enum.uniq_by(struct_entities, & &1.name)

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

    fields_runtime =
      Enum.map(struct_entities, fn
        %Field{} = f ->
          %{
            kind: if(f.__dynamic__, do: :dynamic_field, else: :field),
            name: f.name,
            type: Macro.to_string(f.type),
            enforce: f.enforce,
            derive: f.derives || f.derive,
            __derive_ops__: f.__derive_ops__,
            __from_path__: f.__from_path__,
            __on_path__: f.__on_path__,
            __domain_ops__: f.__domain_ops__,
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
            type: Macro.to_string(sf.type),
            enforce: sf.enforce,
            derive: sf.derives || sf.derive,
            __derive_ops__: sf.__derive_ops__,
            __from_path__: sf.__from_path__,
            __on_path__: sf.__on_path__,
            __domain_ops__: sf.__domain_ops__,
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
            type: Macro.to_string(cf.type),
            enforce: cf.enforce,
            derive: cf.derives || cf.derive,
            __derive_ops__: cf.__derive_ops__,
            __from_path__: cf.__from_path__,
            __on_path__: cf.__on_path__,
            __domain_ops__: cf.__domain_ops__,
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

    virtual_runtime =
      Enum.map(virtual_entities, fn %VirtualField{} = vf ->
        %{
          kind: :virtual_field,
          name: vf.name,
          type: Macro.to_string(vf.type),
          enforce: vf.enforce,
          derive: vf.derives || vf.derive,
          __derive_ops__: vf.__derive_ops__,
          __from_path__: vf.__from_path__,
          __on_path__: vf.__on_path__,
          __domain_ops__: vf.__domain_ops__,
          validator: vf.validator,
          auto: vf.auto,
          on: vf.on,
          from: vf.from,
          domain: vf.domain,
          hint: vf.hint,
          default: vf.default
        }
      end)

    {keys, defstruct_kw, types, enforce_keys, fields_runtime ++ virtual_runtime}
  end

  # Spark partitions conditional_field children into separate :fields,
  # :sub_fields, :conditional_fields lists; sort by `:type` AST line metadata
  # to restore source-declaration order.
  defp merge_children_in_source_order(%ConditionalField{} = cf) do
    (cf.fields ++ cf.sub_fields ++ cf.conditional_fields)
    |> Enum.sort_by(&entity_line/1)
  end

  defp entity_line(%{type: type_ast}) do
    extract_line(type_ast)
  end

  defp entity_line(_), do: 0

  defp extract_line({_, meta, _}) when is_list(meta), do: Keyword.get(meta, :line, 0)
  defp extract_line({_, meta, _, _}) when is_list(meta), do: Keyword.get(meta, :line, 0)
  defp extract_line(_), do: 0

  defp encode_children(entities) do
    {result, _} =
      Enum.reduce(entities, {[], 0}, fn
        %Field{} = f, {acc, sf_count} ->
          encoded = %{
            kind: :field,
            name: f.name,
            derive: f.derives || f.derive,
            __derive_ops__: f.__derive_ops__,
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
            derive: sf.derives || sf.derive,
            __derive_ops__: sf.__derive_ops__,
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
            derive: cf.derives || cf.derive,
            __derive_ops__: cf.__derive_ops__,
            validator: cf.validator,
            hint: cf.hint,
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

  # Like `Macro.escape/1`, but reconstructs any `%Regex{}` from its source at
  # load time. A compiled regex holds a `#Reference` on OTP 27+ (PCRE2),
  # which `Macro.escape/1` can only bake into a module on Elixir >= 1.19.
  # Recompiling from source keeps the baked value a real `%Regex{}` on every
  # supported Elixir/OTP combo.
  def escape_runtime(%Regex{source: source, opts: opts}) do
    quote do: Regex.compile!(unquote(source), unquote(Macro.escape(opts)))
  end

  def escape_runtime(list) when is_list(list), do: Enum.map(list, &escape_runtime/1)

  def escape_runtime({a, b}), do: {escape_runtime(a), escape_runtime(b)}

  def escape_runtime(tuple) when is_tuple(tuple) do
    {:{}, [], tuple |> Tuple.to_list() |> Enum.map(&escape_runtime/1)}
  end

  def escape_runtime(%{__struct__: _} = struct), do: Macro.escape(struct)

  def escape_runtime(map) when is_map(map) do
    {:%{}, [], Enum.map(map, fn {k, v} -> {escape_runtime(k), escape_runtime(v)} end)}
  end

  def escape_runtime(other), do: Macro.escape(other)

  defp example_value_ast(%Field{default: default}, _path) when not is_nil(default),
    do: escape_runtime(default)

  defp example_value_ast(%Field{struct: mod}, _path) when is_atom(mod) and not is_nil(mod) do
    quote do: unquote(mod).example()
  end

  defp example_value_ast(%Field{structs: mod}, _path)
       when is_atom(mod) and mod not in [nil, true, false] do
    quote do: [unquote(mod).example()]
  end

  defp example_value_ast(%Field{type: type}, _path), do: escape_runtime(type_default_ast(type))

  defp example_value_ast(%SubField{default: default}, _path) when not is_nil(default),
    do: escape_runtime(default)

  defp example_value_ast(%SubField{name: name}, _path) do
    component = atom_to_module(name)
    quote do: Module.concat(__MODULE__, unquote(component)).example()
  end

  defp example_value_ast(%ConditionalField{default: default}, _path) when not is_nil(default),
    do: escape_runtime(default)

  defp example_value_ast(%ConditionalField{}, _path), do: nil

  defp example_value_ast(_other, _path), do: nil

  # Heuristic placeholder values for common type ASTs. Anything we don't
  # recognise falls back to nil — the user can always set `default:` to
  # override.
  defp type_default_ast({{:., _, [{:__aliases__, _, [:String]}, :t]}, _, _}), do: ""
  defp type_default_ast({:integer, _, _}), do: 0
  defp type_default_ast({:non_neg_integer, _, _}), do: 0
  defp type_default_ast({:pos_integer, _, _}), do: 1
  defp type_default_ast({:float, _, _}), do: 0.0
  defp type_default_ast({:number, _, _}), do: 0
  defp type_default_ast({:boolean, _, _}), do: false
  defp type_default_ast({:atom, _, _}), do: :placeholder
  defp type_default_ast({:list, _, _}), do: []
  defp type_default_ast({:map, _, _}), do: %{}
  defp type_default_ast({:any, _, _}), do: nil
  defp type_default_ast({:term, _, _}), do: nil
  defp type_default_ast(_other), do: nil
end
