defmodule GuardedStruct.Runtime do
  @moduledoc false

  import GuardedStruct.Messages, only: [translated_message: 1, translated_message: 2]

  alias GuardedStruct.Derive
  alias GuardedStruct.Derive.Parser
  alias GuardedStruct.Derive.ValidationDerive

  # A `struct:` option that names a module.
  defguardp is_struct_module(value) when is_atom(value) and not is_nil(value)

  # A `structs:` option that names a module, not the `true` or `false` flag.
  defguardp is_structs_module(value) when is_atom(value) and value not in [nil, true, false]

  @doc """
  Run the validation pipeline and return `{:ok, attrs_map}` (NOT a struct).
  Used by `GuardedStruct.AshResource` — Ash resources have their own struct,
  so we don't try to make one of ours.
  """
  @spec validate(module(), map() | tuple(), boolean()) ::
          {:ok, map()} | {:error, any()}
  def validate(module, attrs, error? \\ false)

  def validate(module, attrs, error?) when is_map(attrs) do
    # Auto-map cascade: every nested wrap call (sub_field, list-of-sub_field,
    # external `struct:` ref, conditional) returns a plain map instead of a
    # struct. Implemented via a process-dict flag so we don't have to thread
    # the option through every function signature.
    #
    # Safety: `Process.put/2` returns the PRIOR value (or `nil`). We save it
    # and restore on `after` so re-entrant calls (e.g. a validator MFA that
    # itself calls `__guarded_change__/1` on a related resource) don't
    # clobber the outer context. Concurrency-safe because process dicts are
    # process-local — sibling tasks don't see this flag.
    #
    # Speed: one `Process.put` + one `Process.put`/`Process.delete` per
    # top-level call. The wrap closure short-circuits on `build_struct? =
    # false` so non-Ash callers pay zero dict lookups.
    prior = Process.put(:guarded_as_map?, true)
    previous_module = push_current_module(module)

    try do
      do_pipeline(module, attrs, attrs, :add, error?, [], _build_struct? = false)
    after
      pop_current_module(previous_module)

      case prior do
        nil -> Process.delete(:guarded_as_map?)
        v -> Process.put(:guarded_as_map?, v)
      end
    end
  end

  def validate(_module, _attrs, _error?) do
    {:error, [bad_parameters_error(:__root__)]}
  end

  @spec build(module(), map() | struct() | tuple(), boolean()) ::
          {:ok, struct()} | {:error, any()}
  def build(module, attrs, error?)

  def build(module, attrs, error?) when is_struct(attrs) do
    build(module, Map.from_struct(attrs), error?)
  end

  def build(module, attrs, error?) when is_map(attrs) do
    with_telemetry(module, fn ->
      do_build(module, attrs, attrs, :add, error?)
    end)
  end

  def build(module, {key, attrs}, error?) when is_atom(key) or is_list(key) do
    with_telemetry(module, fn ->
      do_build_with_key(module, key, attrs, :add, error?)
    end)
  end

  def build(module, {key, attrs, type}, error?)
      when (is_atom(key) or is_list(key)) and type in [:add, :edit] do
    with_telemetry(module, fn ->
      do_build_with_key(module, key, attrs, type, error?)
    end)
  end

  def build(module, {:__nested__, local_attrs, full_attrs, path, type}, error?) do
    do_build(module, local_attrs, full_attrs, type, error?, path)
  end

  def build(_module, _attrs, _error?) do
    {:error, [bad_parameters_error(:__root__)]}
  end

  defp with_telemetry(module, fun) do
    start = System.monotonic_time()
    metadata = %{module: module}

    previous_module = push_current_module(module)

    :telemetry.execute(
      [:guarded_struct, :builder, :start],
      %{system_time: System.system_time()},
      metadata
    )

    try do
      result = fun.()
      duration = System.monotonic_time() - start

      :telemetry.execute(
        [:guarded_struct, :builder, :stop],
        %{duration: duration},
        Map.merge(metadata, telemetry_result(result))
      )

      result
    rescue
      e ->
        duration = System.monotonic_time() - start

        :telemetry.execute(
          [:guarded_struct, :builder, :exception],
          %{duration: duration},
          Map.merge(metadata, %{kind: :error, reason: e, stacktrace: __STACKTRACE__})
        )

        reraise(e, __STACKTRACE__)
    after
      pop_current_module(previous_module)
    end
  end

  @doc false
  def with_current_module(module, fun) do
    previous = push_current_module(module)

    try do
      fun.()
    after
      pop_current_module(previous)
    end
  end

  # Push the current module onto the process dictionary so per-module
  # `derive_extensions` lookups in Extension.dispatch_*/2,3 and the
  # `validate_derive` / `sanitize_derive` lookups in Derive.fallback_modules/1
  # can find it. Nested sub_field builds inherit; external `struct: Other`
  # calls push their own and restore the previous on return.
  defp push_current_module(module) do
    previous = Process.get(:guarded_struct_current_module)
    Process.put(:guarded_struct_current_module, module)
    previous
  end

  defp pop_current_module(nil), do: Process.delete(:guarded_struct_current_module)
  defp pop_current_module(previous), do: Process.put(:guarded_struct_current_module, previous)

  defp telemetry_result({:ok, _}), do: %{result: :ok}

  defp telemetry_result({:error, errs}) when is_list(errs),
    do: %{result: :error, error_count: length(errs)}

  defp telemetry_result({:error, _}), do: %{result: :error, error_count: 1}

  @spec build_pattern_map(module(), term(), boolean()) ::
          {:ok, map()} | {:error, list()}
  def build_pattern_map(module, attrs, error?)

  def build_pattern_map(_module, attrs, _error?) when not is_map(attrs) do
    {:error, [bad_parameters_error(:__root__)]}
  end

  def build_pattern_map(module, attrs, error?) do
    pattern_fields = module.__fields__()

    with {:ok, _} <- run_pattern_whole_map_derive(attrs, pattern_fields),
         {:ok, validated} <- process_pattern_entries(attrs, pattern_fields, module) do
      {:ok, validated}
    else
      {:error, errs} -> handle_error({:error, errs}, module, error?)
    end
  end

  defp run_pattern_whole_map_derive(attrs, pattern_fields) do
    case Enum.find(pattern_fields, &Map.get(&1, :__derive_ops__)) do
      nil ->
        {:ok, attrs}

      f ->
        ops = f.__derive_ops__
        input = %{field: :__map__, derive_ops: ops}

        case Derive.derive({:ok, %{__map__: attrs}, [input]}) do
          {:ok, %{__map__: validated}} -> {:ok, validated}
          {:error, errs} -> {:error, errs}
        end
    end
  end

  defp process_pattern_entries(attrs, pattern_fields, _module) do
    {results, errors} =
      Enum.reduce(attrs, {%{}, []}, fn {key, value}, acc ->
        put_pattern_entry(acc, key, value, pattern_fields)
      end)

    case errors do
      [] -> {:ok, results}
      _ -> {:error, Enum.reverse(errors)}
    end
  end

  defp put_pattern_entry({ok, errs}, key, value, pattern_fields) do
    key_str = if is_atom(key), do: Atom.to_string(key), else: to_string(key)

    case Enum.find(pattern_fields, &Regex.match?(&1.pattern, key_str)) do
      nil ->
        error = %{
          field: :__map__,
          key: key_str,
          action: :key_pattern,
          message: "key #{inspect(key_str)} does not match any declared pattern"
        }

        {ok, [error | errs]}

      %{} = pf ->
        case process_pattern_value(pf, value, key_str) do
          {:ok, validated_value} -> {Map.put(ok, key_str, validated_value), errs}
          {:error, value_errs} -> {ok, value_errs ++ errs}
        end
    end
  end

  defp process_pattern_value(%{struct: target_mod} = _pf, value, key_str)
       when is_atom(target_mod) and not is_nil(target_mod) do
    case target_mod.builder(value) do
      {:ok, built} -> {:ok, built}
      {:error, errs} when is_list(errs) -> {:error, prefix_key(errs, key_str)}
      {:error, err} -> {:error, prefix_key([err], key_str)}
    end
  end

  defp process_pattern_value(%{validator: {mod, fun}}, value, key_str)
       when is_atom(mod) and is_atom(fun) do
    case apply(mod, fun, [key_str, value]) do
      {:ok, _key, validated} -> {:ok, validated}
      {:ok, validated} -> {:ok, validated}
      {:error, _key, message} -> {:error, [pattern_validator_error(key_str, message)]}
      {:error, message} -> {:error, [pattern_validator_error(key_str, message)]}
      _ -> {:ok, value}
    end
  end

  defp process_pattern_value(_pf, value, _key_str), do: {:ok, value}

  defp pattern_validator_error(key_str, message),
    do: %{field: :__map__, key: key_str, action: :validator, message: message}

  defp prefix_key(errs, key_str) do
    Enum.map(errs, fn
      %{} = e -> Map.put(e, :key, key_str)
      other -> %{key: key_str, error: other}
    end)
  end

  defp do_build_with_key(module, :root, attrs, type, error?),
    do: do_build(module, attrs, attrs, type, error?)

  defp do_build_with_key(module, [:root], attrs, type, error?),
    do: do_build(module, attrs, attrs, type, error?)

  defp do_build_with_key(module, key, attrs, type, error?) when is_list(key) do
    case get_in(attrs, key) do
      sub when is_map(sub) -> do_build(module, sub, attrs, type, error?)
      _ -> {:error, [bad_parameters_error(:__root__)]}
    end
  end

  defp do_build_with_key(module, key, attrs, type, error?) when is_atom(key) do
    case Map.get(attrs, key) do
      sub when is_map(sub) -> do_build(module, sub, attrs, type, error?)
      _ -> {:error, [bad_parameters_error(:__root__)]}
    end
  end

  defp do_build(module, attrs, full_attrs, type, error?, path \\ [])

  defp do_build(module, attrs, full_attrs, type, error?, path) when not is_map(attrs) do
    do_build(module, %{}, full_attrs, type, error?, path)
  end

  defp do_build(module, attrs, full_attrs, type, error?, path) when is_map(attrs) do
    do_pipeline(module, attrs, full_attrs, type, error?, path, _build_struct? = true)
  end

  defp do_pipeline(module, attrs, full_attrs, type, error?, path, build_struct?)
       when is_map(attrs) do
    {info, fields_meta} = read_metadata(module)
    section_opts = section_options_from(info)

    # A nested build receives `full_attrs` already converted by the root build.
    full_attrs_atomized = if path == [], do: atomize(module, full_attrs), else: full_attrs

    with {:ok, normalized} <- normalize_keys(attrs, module),
         {:ok, attrs_after_authorized} <-
           authorized_fields(normalized, info.keys, section_opts.authorized_fields),
         :ok <- check_enforce_keys(attrs_after_authorized, info.enforce_keys),
         {:ok, prepared} <-
           apply_core_keys(attrs_after_authorized, fields_meta, full_attrs_atomized, type) do
      ctx = %{
        module: module,
        info: info,
        fields_meta: fields_meta,
        section_opts: section_opts,
        full_attrs: full_attrs_atomized,
        path: path,
        build_struct?: build_struct?,
        error?: error?
      }

      build_prepared(prepared, ctx)
    else
      {:error, errs} when is_list(errs) ->
        handle_error({:error, errs}, module, error?)
    end
  end

  # Fills `auto` values, checks `domain` and `on`, then copies `from` values into the attrs.
  defp apply_core_keys(attrs, fields_meta, full_attrs, type) do
    with_auto = apply_auto(attrs, fields_meta, type)

    with {:ok, _} <- check_domain(full_attrs, with_auto, fields_meta),
         {:ok, _} <- check_on(with_auto, fields_meta, full_attrs) do
      {:ok, apply_from(with_auto, fields_meta, full_attrs)}
    end
  end

  defp build_prepared(attrs, %{module: module, fields_meta: fields_meta} = ctx) do
    {:ok, sub_field_data, sub_errors} =
      build_sub_fields(attrs, fields_meta, module, ctx.full_attrs, ctx.path)

    already_errored = Enum.map(sub_errors, & &1.field)
    attrs_for_validation = Map.drop(attrs, already_errored)

    {validator_attrs, validator_errors} =
      run_per_field_validators_collect(attrs_for_validation, fields_meta, module)

    all_errors = sub_errors ++ validator_errors

    # The Ash-extension entry point (`validate/3`) sets `:guarded_as_map?`
    # on the process dict, forcing every nested build to return a map
    # rather than a struct, regardless of the `build_struct?` arg the
    # submodule passes in via its own `builder/1`. The map starts from the
    # struct's defaults, the ones `struct/2` fills for `builder/1`.
    # `build_struct? = false` is the non-struct path (`validate/3` itself),
    # so the dict is not read in that case.
    wrap_ctx =
      Map.merge(ctx, %{
        as_map?: ctx.build_struct? and Process.get(:guarded_as_map?, false),
        virtual_names: Map.get(ctx.info, :virtual_keys, []),
        failed: MapSet.new(all_errors, & &1.field)
      })

    {derive_errors, struct_value} =
      case run_main_validator(validator_attrs, module, ctx.section_opts) do
        {:ok, after_main} ->
          derive_merged(Map.merge(after_main, sub_field_data), wrap_ctx)

        {:error, errs} ->
          {errs, wrap_value(Map.merge(validator_attrs, sub_field_data), wrap_ctx)}
      end

    case derive_errors ++ all_errors do
      [] -> {:ok, struct_value}
      final_errors -> handle_error({:error, final_errors}, module, ctx.error?)
    end
  end

  # Runs the derives in two passes and returns `{errors, value}`.
  #
  # Pass 1 derives the virtual fields on the raw merged map: `wrap_value/2`
  # drops them, so this is the one chance to validate them.
  # Pass 2 wraps the map into the struct (so `struct/2` applies field defaults),
  # then derives the non-virtual fields on it.
  #
  # A field that already failed its validator or its sub_field has no value left to derive:
  # its derives would run on the default and report a second, unrelated error
  # (`not_nil_value` on the nil it was dropped to), so it is skipped.
  defp derive_merged(merged, %{module: module, failed: failed} = ctx) do
    derivable? = &(not MapSet.member?(failed, &1.name))

    virtual_meta =
      ctx.virtual_names |> Enum.map(&module.__field_meta__/1) |> Enum.filter(derivable?)

    virtual_errs =
      case run_derives(merged, virtual_meta) do
        {:ok, _} -> []
        {:error, errs} -> errs
      end

    wrapped = wrap_value(merged, ctx)

    non_virtual_meta =
      ctx.fields_meta
      |> Enum.reject(&(&1[:kind] == :virtual_field))
      |> Enum.filter(derivable?)

    case run_derives(wrapped, non_virtual_meta) do
      {:ok, derived} -> {virtual_errs, derived}
      {:error, errs} -> {virtual_errs ++ errs, wrapped}
    end
  end

  defp wrap_value(merged, %{module: module, virtual_names: virtual_names} = ctx) do
    merged = Map.drop(merged, virtual_names)

    cond do
      ctx.as_map? -> module |> struct() |> Map.from_struct() |> Map.merge(merged)
      ctx.build_struct? -> struct(module, merged)
      true -> merged
    end
  end

  defp read_metadata(module) do
    {module.__guarded_information__(), module.__guarded_fields__()}
  end

  defp section_options_from(info) do
    Map.get(info, :options, %{authorized_fields: false})
  end

  defp normalize_keys(attrs, module) when is_map(attrs) do
    case Map.keys(attrs) |> List.first() do
      nil -> {:ok, attrs}
      _ -> {:ok, atomize(module, attrs)}
    end
  end

  @doc false
  def atomize(module, attrs) do
    Parser.convert_to_atom_map(
      attrs,
      Map.get(module.__guarded_information__(), :dynamic_keys, []),
      module.__guarded_atom_lookup__(),
      nested_conversion([module])
    )
  end

  # How `Parser.convert_to_atom_map/4` treats the map under a key: the nested
  # module(s) the key's value is built by decide which of its keys are
  # `dynamic_field`s, whose values stay as the caller sent them.
  defp nested_conversion(modules) do
    fn key ->
      case Enum.flat_map(modules, &embedded_modules(&1, key)) do
        [] ->
          nil

        embedded ->
          %{
            passthrough:
              Enum.flat_map(embedded, &Map.get(&1.__guarded_information__(), :dynamic_keys, [])),
            nested: nested_conversion(embedded)
          }
      end
    end
  end

  defp embedded_modules(module, key) do
    case module.__guarded_field_meta__(key) do
      nil -> []
      meta -> meta_modules(meta, module)
    end
  end

  defp meta_modules(%{kind: :conditional_field} = meta, owner),
    do: conditional_modules(meta, owner)

  defp meta_modules(%{kind: kind} = meta, _owner) do
    struct = Map.get(meta, :struct)
    structs = Map.get(meta, :structs)

    cond do
      is_structs_module(structs) -> [structs]
      is_struct_module(struct) -> [struct]
      kind == :sub_field -> [meta.child_module]
      true -> []
    end
  end

  defp conditional_modules(%{name: name, children: children}, owner) do
    Enum.flat_map(children, fn
      %{kind: :sub_field, sub_field_index: index} ->
        [sub_field_module(owner, name, index)]

      %{kind: :conditional_field} = inner ->
        conditional_modules(inner, owner)

      child ->
        meta_modules(child, owner)
    end)
  end

  defp authorized_fields(attrs, _keys, false), do: {:ok, attrs}
  defp authorized_fields(attrs, _keys, nil), do: {:ok, attrs}

  defp authorized_fields(attrs, keys, true) do
    extras = Enum.filter(Map.keys(attrs), &(&1 not in keys))

    if extras == [] do
      {:ok, attrs}
    else
      {:error,
       Enum.map(extras, fn field ->
         %{
           field: field,
           action: :authorized_fields,
           message: translated_message(:authorized_fields)
         }
       end)}
    end
  end

  defp check_enforce_keys(_attrs, []), do: :ok

  defp check_enforce_keys(attrs, enforce_keys) do
    missing = Enum.reject(enforce_keys, &Map.has_key?(attrs, &1))

    if missing == [] do
      :ok
    else
      {:error,
       Enum.map(missing, fn field ->
         %{
           field: field,
           action: :required_fields,
           message: translated_message(:required_fields)
         }
       end)}
    end
  end

  defp apply_auto(attrs, fields_meta, type) do
    Enum.reduce(fields_meta, attrs, &put_auto(&2, &1, type))
  end

  # An `:edit` build keeps a value the caller already sent; otherwise the `auto` MFA fills it.
  defp put_auto(attrs, %{auto: nil}, _type), do: attrs

  defp put_auto(attrs, %{auto: auto, name: name}, type) do
    if type == :edit and not is_nil(Map.get(attrs, name)) do
      attrs
    else
      Map.put(attrs, name, call_auto(auto))
    end
  end

  defp call_auto({mod, fun}), do: apply(mod, fun, [])
  defp call_auto({mod, fun, args}) when is_list(args), do: apply(mod, fun, args)
  defp call_auto({mod, fun, arg}), do: apply(mod, fun, [arg])

  defp check_on(attrs, fields_meta, full_attrs) do
    errors =
      fields_meta
      |> Enum.reverse()
      |> Enum.flat_map(fn
        %{on: nil} ->
          []

        %{on: pattern, name: name} = f ->
          [check_on_pattern(name, pattern, attrs, full_attrs, Map.get(f, :__on_path__))]

        _ ->
          []
      end)
      |> Enum.reject(&is_nil/1)

    if errors == [], do: {:ok, attrs}, else: {:error, errors}
  end

  defp check_on_pattern(field_name, pattern, attrs, full_attrs, pre_parsed) do
    [head | rest] = path = pre_parsed || Parser.parse_core_keys_pattern(pattern)
    field_value = Map.get(full_attrs, field_name) || Map.get(attrs, field_name)

    if is_nil(field_value) do
      nil
    else
      target =
        if head == :root,
          do: get_in(full_attrs, rest),
          else: get_in(attrs, path)

      if is_nil(target) do
        %{
          message: translated_message(:check_dependent_keys, {field_name, path}),
          field: field_name,
          action: :dependent_keys
        }
      end
    end
  end

  defp apply_from(attrs, fields_meta, full_attrs) do
    Enum.reduce(fields_meta, attrs, fn
      %{from: nil}, acc ->
        acc

      %{from: pattern, name: name} = f, acc ->
        [head | rest] =
          path = Map.get(f, :__from_path__) || Parser.parse_core_keys_pattern(pattern)

        source =
          if head == :root,
            do: get_in(full_attrs, rest),
            else: get_in(acc, path)

        case source do
          nil -> acc
          value -> Map.put(acc, name, value)
        end

      _, acc ->
        acc
    end)
  end

  defp check_domain(full_attrs, attrs, fields_meta) do
    errors =
      fields_meta
      |> Enum.flat_map(fn
        %{domain: nil} ->
          []

        %{name: name} = f ->
          rules = Map.get(f, :__domain_ops__) || []
          run_domain_rules(rules, name, full_attrs, attrs)
      end)
      |> List.flatten()

    if errors == [], do: {:ok, attrs}, else: {:error, errors}
  end

  defp run_domain_rules([], _key, _full_attrs, _attrs), do: []

  defp run_domain_rules(rules, key, full_attrs, attrs) do
    case Map.get(full_attrs, key) || Map.get(attrs, key) do
      nil ->
        []

      _ ->
        Enum.map(rules, &run_domain_rule(&1, key, full_attrs)) |> Enum.reject(&is_nil/1)
    end
  end

  defp run_domain_rule(
         %{field_path: field, validator: validator, required?: required?},
         key,
         full_attrs
       ) do
    domain_field = get_domain_field(field, full_attrs)

    cond do
      not is_nil(domain_field) ->
        case ValidationDerive.validate(validator, domain_field, key) do
          data when is_tuple(data) and elem(data, 0) == :error ->
            %{
              message: translated_message(:domain_field_status, key),
              field_path: field,
              field: key,
              action: :domain_parameters
            }

          _ ->
            nil
        end

      not required? ->
        nil

      true ->
        %{
          message: translated_message(:force_domain_field_status, key),
          field_path: field,
          field: key,
          action: :domain_parameters
        }
    end
  end

  # The domain path comes from the developer's DSL, not from user input.
  # sobelow_skip ["DOS.StringToAtom"]
  defp get_domain_field(field, attrs) do
    field
    |> String.trim()
    |> String.split(".", trim: true)
    |> Enum.map(&String.to_atom/1)
    |> then(&get_in(attrs, &1))
  end

  defp build_sub_fields(attrs, fields_meta, parent_module, full_attrs, parent_path) do
    first_by_name = Enum.reduce(fields_meta, %{}, &Map.put_new(&2, &1.name, &1))

    embedded =
      attrs
      |> Map.keys()
      |> Enum.flat_map(&embedded_meta(first_by_name, &1))

    Enum.reduce(embedded, {:ok, %{}, []}, fn meta, acc ->
      value = Map.get(attrs, meta.name)
      build_sub_field(meta, value, acc, parent_module, full_attrs, parent_path)
    end)
  end

  defp embedded_meta(first_by_name, key) do
    case Map.get(first_by_name, key) do
      nil -> []
      meta -> if meta.kind == :conditional_field or embedded?(meta), do: [meta], else: []
    end
  end

  defp build_sub_field(_meta, nil, acc, _parent_module, _full_attrs, _parent_path), do: acc

  defp build_sub_field(meta, value, {:ok, ok_acc, err_acc}, parent_module, full_attrs, path) do
    with {:ok, validated} <- run_pre_validator(meta, value, parent_module),
         {:ok, prepared} <- pre_derive(meta, validated) do
      dispatch(meta, prepared, parent_module, ok_acc, err_acc, full_attrs, path)
    else
      {:error, errs} -> {:ok, ok_acc, err_acc ++ [%{field: meta.name, errors: errs}]}
    end
  end

  defp run_pre_validator(%{validator: {mod, fun}, name: name}, value, _parent)
       when is_atom(mod) and is_atom(fun) do
    apply_validator(mod, fun, name, value)
  end

  defp run_pre_validator(%{struct: m} = meta, value, _parent) when is_struct_module(m) do
    apply_caller_validator(m, meta.name, value)
  end

  defp run_pre_validator(%{structs: m} = meta, value, _parent) when is_structs_module(m) do
    apply_caller_validator(m, meta.name, value)
  end

  defp run_pre_validator(%{kind: :sub_field, name: name}, value, parent) do
    apply_caller_validator(parent, name, value)
  end

  defp run_pre_validator(_meta, value, _parent), do: {:ok, value}

  defp apply_validator(mod, fun, field, value) do
    case apply(mod, fun, [field, value]) do
      {:ok, _key, new_value} ->
        {:ok, new_value}

      {:error, key, message} ->
        {:error, %{field: key, message: message, action: :validator}}
    end
  end

  defp apply_caller_validator(mod, field, value) do
    if mod.__guarded_has_validator__() do
      case mod.validator(field, value) do
        {:ok, _key, new_value} -> {:ok, new_value}
        {:error, key, message} -> {:error, %{field: key, message: message, action: :validator}}
        _ -> {:ok, value}
      end
    else
      {:ok, value}
    end
  end

  # A conditional field runs its derive per branch, in `dispatch_conditional/7`.
  defp pre_derive(%{kind: :conditional_field}, value), do: {:ok, value}

  defp pre_derive(%{__derive_ops__: ops, name: name}, value) when not is_nil(ops),
    do: derive_value(name, ops, value)

  defp pre_derive(_meta, value), do: {:ok, value}

  defp derive_value(name, ops, value) do
    input = %{field: name, derive_ops: ops}

    case Derive.derive({:ok, %{name => value}, [input]}) do
      {:ok, %{^name => sanitized}} -> {:ok, sanitized}
      {:error, errs} -> {:error, errs}
    end
  end

  defp dispatch(meta, value, parent_module, ok_acc, err_acc, full_attrs, parent_path) do
    case dispatch_target(meta, value) do
      :conditional ->
        dispatch_conditional(meta, value, parent_module, ok_acc, err_acc, full_attrs, parent_path)

      {:list, module} ->
        build_list(module, meta.name, value, ok_acc, err_acc, full_attrs, parent_path)

      {:single, module} ->
        build_single(module, meta.name, value, ok_acc, err_acc, full_attrs, parent_path)

      :shape_error ->
        {:ok, ok_acc, err_acc ++ shape_error(meta)}
    end
  end

  # Which module builds the value, and whether it builds a list or one struct.
  defp dispatch_target(%{kind: :conditional_field}, _value), do: :conditional

  defp dispatch_target(%{structs: structs}, value)
       when is_structs_module(structs) and is_list(value),
       do: {:list, structs}

  defp dispatch_target(%{struct: struct}, value) when is_struct_module(struct) and is_map(value),
    do: {:single, struct}

  defp dispatch_target(%{kind: :sub_field, list?: true} = meta, value) when is_list(value),
    do: {:list, meta.child_module}

  defp dispatch_target(%{kind: :sub_field, list?: true}, _value), do: :shape_error

  defp dispatch_target(%{kind: :sub_field} = meta, value) when is_map(value),
    do: {:single, meta.child_module}

  defp dispatch_target(_meta, _value), do: :shape_error

  # A `struct:`, `structs:` or `sub_field` value of the wrong shape is refused, instead of being
  # kept in the struct unbuilt: a list where a list is built, a map where one struct is built.
  defp shape_error(meta) do
    cond do
      Map.get(meta, :list?) == true or is_structs_module(meta.structs) ->
        [%{field: meta.name, action: :type, message: translated_message(:list_builder_type)}]

      meta.kind == :sub_field or is_struct_module(meta.struct) ->
        [bad_parameters_error(meta.name)]

      true ->
        []
    end
  end

  defp dispatch_conditional(meta, value, parent_module, ok_acc, err_acc, full_attrs, parent_path) do
    children = meta.children
    new_path = parent_path ++ [meta.name]

    case run_child_derive(meta, value) do
      {:ok, value} ->
        do_dispatch_conditional(
          meta,
          value,
          parent_module,
          ok_acc,
          err_acc,
          full_attrs,
          new_path,
          children
        )

      {:error, derive_errs} ->
        {:ok, ok_acc,
         err_acc ++ [%{field: meta.name, errors: derive_errs, action: :conditionals}]}
    end
  end

  defp do_dispatch_conditional(
         meta,
         value,
         parent_module,
         ok_acc,
         err_acc,
         full_attrs,
         new_path,
         children
       ) do
    if meta.list? == true and is_list(value) do
      results =
        Enum.map(value, fn item ->
          try_conditional_children(item, children, meta, parent_module, full_attrs, new_path)
        end)

      collect_list_conditional_results(results, meta, ok_acc, err_acc)
    else
      case try_conditional_children(value, children, meta, parent_module, full_attrs, new_path) do
        {:ok, built} ->
          {:ok, Map.put(ok_acc, meta.name, built), err_acc}

        {:error, child_errors} ->
          final_errors = priority_errors(meta, child_errors)

          {:ok, ok_acc,
           err_acc ++
             [%{field: meta.name, errors: final_errors, action: :conditionals}]}
      end
    end
  end

  # A `priority: true` conditional field reports only the first failed branch.
  defp priority_errors(%{priority: true}, [first | _]), do: [first]
  defp priority_errors(_meta, errors), do: errors

  defp try_conditional_children(value, children, parent_meta, parent_module, full_attrs, path) do
    Enum.reduce_while(children, {:error, []}, fn child, {:error, errs} ->
      case try_conditional_child(child, value, parent_meta, parent_module, full_attrs, path) do
        {:ok, _} = ok -> {:halt, ok}
        {:error, e} -> {:cont, {:error, append_errors(errs, hint_error(e, child))}}
      end
    end)
  end

  defp append_errors(errs, new_errs) when is_list(new_errs), do: errs ++ new_errs
  defp append_errors(errs, new_err), do: errs ++ [new_err]

  defp hint_error(err, %{hint: nil}), do: err

  defp hint_error(errs, %{hint: h}) when is_list(errs) and is_binary(h),
    do: Enum.map(errs, &Map.put(&1, :__hint__, h))

  defp hint_error(err, %{hint: h}) when is_map(err) and is_binary(h),
    do: Map.put(err, :__hint__, h)

  defp hint_error(err, _), do: err

  defp try_conditional_child(%{kind: :field} = child, value, _parent, _module, _full, _path) do
    with {:ok, validated} <- run_child_validator(child, value) do
      build_conditional_field(child, validated)
    end
  end

  defp try_conditional_child(
         %{kind: :sub_field, name: name} = child,
         value,
         parent,
         parent_module,
         full_attrs,
         path
       ) do
    with {:ok, validated} <- run_child_validator(child, value),
         {:ok, sanitized} <- run_child_derive(child, validated) do
      submodule =
        case Map.get(child, :sub_field_index) do
          index when index in [nil, false] -> sub_field_module(parent_module, name)
          index -> sub_field_module(parent_module, parent.name, index)
        end

      nested_input_for = fn v -> {:__nested__, v, full_attrs, path, :add} end
      build_conditional_sub_field(child, sanitized, submodule, nested_input_for)
    end
  end

  defp try_conditional_child(
         %{kind: :conditional_field} = child,
         value,
         _parent,
         parent_module,
         full_attrs,
         path
       ) do
    list? = Map.get(child, :structs) == true or Map.get(child, :list?) == true
    try_nested_conditional(list?, child, value, parent_module, full_attrs, path)
  end

  defp build_conditional_field(%{struct: struct}, validated)
       when is_struct_module(struct) and is_map(validated),
       do: struct.builder(validated)

  defp build_conditional_field(%{struct: struct} = child, _validated)
       when is_struct_module(struct),
       do: {:error, [bad_parameters_error(Map.get(child, :name, :__root__))]}

  defp build_conditional_field(%{structs: structs}, validated)
       when is_structs_module(structs) and is_list(validated) do
    validated
    |> Enum.flat_map(fn
      item when is_list(item) -> Enum.map(item, &structs.builder/1)
      item -> [structs.builder(item)]
    end)
    |> collect_built()
  end

  defp build_conditional_field(%{structs: structs} = child, _validated)
       when is_structs_module(structs),
       do:
         {:error,
          %{message: translated_message(:list_builder_type), field: child.name, action: :type}}

  defp build_conditional_field(child, validated), do: run_child_derive(child, validated)

  defp build_conditional_sub_field(%{list?: true} = child, sanitized, submodule, input_for)
       when is_list(sanitized) do
    sanitized
    |> Enum.flat_map(&build_conditional_item(&1, child, submodule, input_for))
    |> collect_built()
  end

  defp build_conditional_sub_field(
         %{list?: true, name: name},
         _sanitized,
         _submodule,
         _input_for
       ),
       do:
         {:error, %{message: translated_message(:list_builder_type), field: name, action: :type}}

  defp build_conditional_sub_field(_child, sanitized, submodule, input_for)
       when is_map(sanitized),
       do: submodule.builder(input_for.(sanitized))

  defp build_conditional_sub_field(_child, _sanitized, _submodule, _input_for),
    do: {:error, [bad_parameters_error(:__root__)]}

  defp build_conditional_item(item, _child, submodule, input_for) when is_map(item),
    do: [submodule.builder(input_for.(item))]

  defp build_conditional_item(item, _child, submodule, input_for) when is_list(item),
    do: Enum.map(item, &submodule.builder(input_for.(&1)))

  defp build_conditional_item(_item, child, _submodule, _input_for),
    do: [{:error, [bad_parameters_error(Map.get(child, :name, :__root__))]}]

  defp try_nested_conditional(true, child, value, parent_module, full_attrs, path)
       when is_list(value) do
    results =
      Enum.map(value, fn item ->
        try_conditional_children(item, child.children, child, parent_module, full_attrs, path)
      end)

    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {oks, []} ->
        {:ok, Enum.map(oks, fn {:ok, v} -> v end)}

      {_oks, errs} ->
        collected =
          errs
          |> Enum.flat_map(fn {:error, e} -> e end)
          |> Enum.uniq()

        {:error, %{field: child.name, errors: collected, action: :conditionals}}
    end
  end

  defp try_nested_conditional(true, child, _value, _parent_module, _full_attrs, _path) do
    {:error, %{field: child.name, message: translated_message(:list_builder_type), action: :type}}
  end

  defp try_nested_conditional(false, child, value, parent_module, full_attrs, path) do
    case try_conditional_children(value, child.children, child, parent_module, full_attrs, path) do
      {:ok, _} = ok -> ok
      {:error, errs} -> {:error, %{field: child.name, errors: errs, action: :conditionals}}
    end
  end

  defp run_child_derive(%{derive: nil}, value), do: {:ok, value}

  defp run_child_derive(%{name: name} = child, value) do
    if has_derive?(child),
      do: derive_value(name, Map.get(child, :__derive_ops__), value),
      else: {:ok, value}
  end

  defp run_child_derive(_child, value), do: {:ok, value}

  defp has_derive?(meta),
    do: not (is_nil(Map.get(meta, :__derive_ops__)) and is_nil(Map.get(meta, :derive)))

  defp run_child_validator(%{validator: {mod, fun}, name: name}, value)
       when is_atom(mod) and is_atom(fun),
       do: apply_validator(mod, fun, name, value)

  defp run_child_validator(_child, value), do: {:ok, value}

  defp collect_list_conditional_results(results, meta, ok_acc, err_acc) do
    {oks, errs} =
      Enum.reduce(results, {[], []}, fn
        {:ok, val}, {oks, errs} -> {oks ++ [val], errs}
        {:error, errors}, {oks, errs} -> {oks, errs ++ errors}
      end)

    case priority_errors(meta, Enum.uniq(errs)) do
      [] ->
        {:ok, Map.put(ok_acc, meta.name, oks), err_acc}

      final_errs ->
        {:ok, ok_acc, err_acc ++ [%{field: meta.name, errors: final_errs, action: :conditionals}]}
    end
  end

  defp build_single(module, field_name, value, ok_acc, err_acc, full_attrs, parent_path) do
    new_path = parent_path ++ [field_name]
    nested_input = {:__nested__, value, full_attrs, new_path, :add}

    case with_module_context(module, fn -> module.builder(nested_input) end) do
      {:ok, built} ->
        {:ok, Map.put(ok_acc, field_name, built), err_acc}

      {:error, errs} ->
        {:ok, ok_acc, err_acc ++ [%{field: field_name, errors: errs}]}
    end
  end

  defp build_list(module, field_name, list, ok_acc, err_acc, full_attrs, parent_path) do
    new_path = parent_path ++ [field_name]

    built =
      Enum.map(list, fn item ->
        with_module_context(module, fn ->
          module.builder({:__nested__, item, full_attrs, new_path, :add})
        end)
      end)

    case collect_built(built) do
      {:ok, values} -> {:ok, Map.put(ok_acc, field_name, values), err_acc}
      {:error, errs} -> {:ok, ok_acc, err_acc ++ [%{field: field_name, errors: errs}]}
    end
  end

  # Returns every built value, or the errors of the first item that failed.
  defp collect_built(built) do
    case Enum.find(built, &(elem(&1, 0) == :error)) do
      nil -> {:ok, Enum.map(built, &elem(&1, 1))}
      {:error, errs} -> {:error, errs}
    end
  end

  # Push `module` onto the process-dict current-module stack so derive
  # extension and fallback lookups inside this build resolve against it. We only
  # push when `module` is a top-level module that declares its own
  # `derive_extensions:` opt or `validate_derive` / `sanitize_derive` section
  # option — otherwise we inherit the caller's pdict (this is how sub_field
  # auto-generated submodules pick up the root user module's settings).
  defp with_module_context(module, fun) do
    if own_derive_settings?(module) do
      previous = push_current_module(module)

      try do
        fun.()
      after
        pop_current_module(previous)
      end
    else
      fun.()
    end
  end

  defp own_derive_settings?(module) do
    info = module.__guarded_information__()
    options = Map.get(info, :options, %{})

    info.path == [] and
      (not is_nil(module.__guarded_derive_extensions_opt__()) or
         Map.get(options, :validate_derive) not in [nil, []] or
         Map.get(options, :sanitize_derive) not in [nil, []])
  end

  defp run_per_field_validators_collect(attrs, _fields_meta, module) do
    Enum.reduce(attrs, {%{}, []}, fn {key, value}, acc ->
      collect_field_validator(acc, module.__field_meta__(key), key, value, module)
    end)
  end

  # Embedded values were already validated by `build_sub_fields/5`, so they pass through.
  defp collect_field_validator({ok_acc, err_acc}, meta, key, value, module) do
    if embedded?(meta) do
      {Map.put(ok_acc, key, value), err_acc}
    else
      case run_field_validator(meta, key, value, module) do
        {:ok, new_value} ->
          {Map.put(ok_acc, key, new_value), err_acc}

        {:error, message} ->
          {ok_acc, err_acc ++ [%{field: key, message: message, action: :validator}]}
      end
    end
  end

  defp embedded?(nil), do: false

  defp embedded?(meta) do
    meta.kind == :sub_field or
      not is_nil(Map.get(meta, :struct)) or
      (not is_nil(Map.get(meta, :structs)) and Map.get(meta, :structs) != false)
  end

  defp run_field_validator(nil, _key, value, _module), do: {:ok, value}
  defp run_field_validator(%{kind: :sub_field}, _key, value, _module), do: {:ok, value}

  defp run_field_validator(%{validator: {mod, fun}}, key, value, _module)
       when is_atom(mod) and is_atom(fun) do
    case apply(mod, fun, [key, value]) do
      {:ok, _key, new_value} -> {:ok, new_value}
      {:error, _key, message} -> {:error, message}
      other -> other
    end
  end

  defp run_field_validator(_meta, key, value, module) do
    if module.__guarded_has_validator__() do
      case module.validator(key, value) do
        {:ok, _key, new_value} -> {:ok, new_value}
        {:error, _key, message} -> {:error, message}
        _ -> {:ok, value}
      end
    else
      {:ok, value}
    end
  end

  defp run_main_validator(attrs, module, section_opts) do
    case call_main_validator(attrs, module, section_opts) do
      {:ok, value} -> {:ok, value}
      {:error, errs} when is_list(errs) -> {:error, errs}
      {:error, err} -> {:error, [err]}
      _ -> {:ok, attrs}
    end
  end

  defp call_main_validator(attrs, _module, %{main_validator: {mod, fun}}),
    do: apply(mod, fun, [attrs])

  defp call_main_validator(attrs, module, _section_opts) do
    if module.__guarded_has_main_validator__(),
      do: module.main_validator(attrs),
      else: {:ok, attrs}
  end

  defp run_derives(value, fields_meta) do
    derive_inputs =
      for f <- fields_meta, has_derive?(f) do
        %{field: f.name, derive_ops: Map.get(f, :__derive_ops__)}
      end

    if derive_inputs == [] do
      {:ok, value}
    else
      {data_map, rewrap} =
        if is_struct(value) do
          {Map.from_struct(value), &struct(value.__struct__, &1)}
        else
          {value, & &1}
        end

      case Derive.derive({:ok, data_map, derive_inputs}) do
        {:ok, processed} -> {:ok, rewrap.(processed)}
        {:error, errors} -> {:error, errors}
      end
    end
  end

  defp handle_error({:error, errs} = result, module, true) do
    case module.__guarded_error_module__() do
      nil -> result
      error_module -> raise error_module, errors: errs, term: nil
    end
  end

  defp handle_error(result, _module, _error?), do: result

  @doc false
  def all_keys(module) do
    Enum.map(module.__information__().keys, fn k ->
      case module.__field_meta__(k) do
        %{kind: :sub_field, child_module: child} -> %{k => all_keys(child)}
        _ -> k
      end
    end)
  end

  @doc false
  def all_enforce_keys(module) do
    Enum.flat_map(module.__information__().enforce_keys, fn k ->
      case module.__field_meta__(k) do
        %{kind: :sub_field, child_module: child} -> [%{k => all_enforce_keys(child)}]
        _ -> [k]
      end
    end)
  end

  defp bad_parameters_error(field),
    do: %{field: field, action: :bad_parameters, message: translated_message(:builder)}

  # The module generated for a sub_field: the owner module plus the camelized field name.
  # The sub_field index tells apart the sub_fields of one conditional field.
  # Module and field names come from the developer's DSL, not from user input.
  # sobelow_skip ["DOS.ModuleConcat"]
  defp sub_field_module(owner, name, index \\ nil),
    do: Module.concat(owner, Macro.camelize("#{name}#{index}"))
end
