defmodule GuardedStruct.Runtime do
  @moduledoc false

  import GuardedStruct.Messages, only: [translated_message: 1, translated_message: 2]

  alias GuardedStruct.Derive
  alias GuardedStruct.Derive.Parser
  alias GuardedStruct.Derive.ValidationDerive

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

    try do
      do_pipeline(module, attrs, attrs, :add, error?, [], _build_struct? = false)
    after
      case prior do
        nil -> Process.delete(:guarded_as_map?)
        v -> Process.put(:guarded_as_map?, v)
      end
    end
  end

  def validate(_module, _attrs, _error?) do
    {:error, [%{field: :__root__, action: :bad_parameters, message: translated_message(:builder)}]}
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
    {:error, [%{field: :__root__, action: :bad_parameters, message: translated_message(:builder)}]}
  end

  defp with_telemetry(module, fun) do
    start = System.monotonic_time()
    metadata = %{module: module}

    # Push the current module onto the process dictionary so per-module
    # `derive_extensions` lookups in Extension.dispatch_*/2,3 can find it.
    # Nested sub_field builds inherit; external `struct: Other` calls push
    # their own and restore the previous on return.
    previous_module = Process.get(:guarded_struct_current_module)
    Process.put(:guarded_struct_current_module, module)

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
      case previous_module do
        nil -> Process.delete(:guarded_struct_current_module)
        prev -> Process.put(:guarded_struct_current_module, prev)
      end
    end
  end

  defp telemetry_result({:ok, _}), do: %{result: :ok}

  defp telemetry_result({:error, errs}) when is_list(errs),
    do: %{result: :error, error_count: length(errs)}

  defp telemetry_result({:error, _}), do: %{result: :error, error_count: 1}
  defp telemetry_result(_), do: %{}

  @spec build_pattern_map(module(), map(), boolean()) ::
          {:ok, map()} | {:error, list()}
  def build_pattern_map(module, attrs, error?)

  def build_pattern_map(_module, attrs, _error?) when not is_map(attrs) do
    {:error, [%{field: :__root__, action: :bad_parameters, message: translated_message(:builder)}]}
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
      Enum.reduce(attrs, {%{}, []}, fn {key, value}, {ok, errs} ->
        key_str = if is_atom(key), do: Atom.to_string(key), else: to_string(key)

        case Enum.find(pattern_fields, &Regex.match?(&1.pattern, key_str)) do
          nil ->
            {ok,
             [
               %{
                 field: :__map__,
                 key: key_str,
                 action: :key_pattern,
                 message: "key #{inspect(key_str)} does not match any declared pattern"
               }
               | errs
             ]}

          %{} = pf ->
            case process_pattern_value(pf, value, key_str) do
              {:ok, validated_value} -> {Map.put(ok, key_str, validated_value), errs}
              {:error, value_errs} -> {ok, value_errs ++ errs}
            end
        end
      end)

    case errors do
      [] -> {:ok, results}
      _ -> {:error, Enum.reverse(errors)}
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
      {:error, _key, message} -> {:error, [%{key: key_str, action: :validator, message: message}]}
      {:error, message} -> {:error, [%{key: key_str, action: :validator, message: message}]}
      _ -> {:ok, value}
    end
  end

  defp process_pattern_value(_pf, value, _key_str), do: {:ok, value}

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
      _ -> {:error, [%{field: :__root__, action: :bad_parameters, message: translated_message(:builder)}]}
    end
  end

  defp do_build_with_key(module, key, attrs, type, error?) when is_atom(key) do
    case Map.get(attrs, key) do
      sub when is_map(sub) -> do_build(module, sub, attrs, type, error?)
      _ -> {:error, [%{field: :__root__, action: :bad_parameters, message: translated_message(:builder)}]}
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

    keys = info.keys
    enforce_keys = info.enforce_keys
    dynamic_field_names = Map.get(info, :dynamic_keys, [])

    full_attrs_atomized = Parser.convert_to_atom_map(full_attrs, dynamic_field_names)

    with {:ok, normalized} <- normalize_keys(attrs, dynamic_field_names),
         {:ok, attrs_after_authorized} <-
           authorized_fields(normalized, keys, section_opts.authorized_fields),
         :ok <- check_enforce_keys(attrs_after_authorized, enforce_keys),
         attrs1 = apply_auto(attrs_after_authorized, fields_meta, type),
         {:ok, _} <- check_domain(full_attrs_atomized, attrs1, fields_meta),
         {:ok, _} <- check_on(attrs1, fields_meta, full_attrs_atomized),
         attrs2 = apply_from(attrs1, fields_meta, full_attrs_atomized) do
      {:ok, sub_field_data, sub_errors} =
        build_sub_fields(attrs2, fields_meta, module, full_attrs_atomized, path)

      already_errored = Enum.map(sub_errors, & &1.field)
      attrs_for_validation = Map.drop(attrs2, already_errored)

      {validator_attrs, validator_errors} =
        run_per_field_validators_collect(attrs_for_validation, fields_meta, module)

      all_errors = sub_errors ++ validator_errors

      virtual_names = Map.get(info, :virtual_keys, [])

      # The Ash-extension entry point (`validate/3`) sets `:guarded_as_map?`
      # on the process dict, forcing every nested build to return a map
      # rather than a struct — regardless of the `build_struct?` arg the
      # submodule passes in via its own `builder/1`. Short-circuit:
      # `build_struct? = false` is the original non-struct path (`validate/3`
      # itself), so we don't need to consult the dict in that case.
      wrap_as_struct? =
        build_struct? and not Process.get(:guarded_as_map?, false)

      wrap = fn merged ->
        merged = Map.drop(merged, virtual_names)
        if wrap_as_struct?, do: struct(module, merged), else: merged
      end

      {derive_errors, struct_value} =
        case run_main_validator(validator_attrs, module) do
          {:ok, after_main} ->
            merged = Map.merge(after_main, sub_field_data)

            # Pass 1 — derive on the raw merged map for VIRTUAL fields only.
            # Virtuals are dropped by `wrap.()`, so this is the one chance
            # to validate them. Defaults aren't relevant here (virtuals
            # don't get default-substituted through struct/2).
            virtual_meta = Enum.map(virtual_names, &module.__field_meta__/1)

            virtual_errs =
              case run_derives(merged, virtual_meta) do
                {:ok, _} -> []
                {:error, errs} -> errs
              end

            # Pass 2 — wrap into struct (so struct/2 applies field defaults),
            # then derive on the wrapped struct for NON-virtual fields.
            sv = wrap.(merged)
            non_virtual_meta = Enum.reject(fields_meta, &(&1[:kind] == :virtual_field))

            case run_derives(sv, non_virtual_meta) do
              {:ok, derived} -> {virtual_errs, derived}
              {:error, errs} -> {virtual_errs ++ errs, sv}
            end

          {:error, errs} when is_list(errs) ->
            {errs, wrap.(Map.merge(validator_attrs, sub_field_data))}

          {:error, err} ->
            {[err], wrap.(Map.merge(validator_attrs, sub_field_data))}
        end

      final_errors = derive_errors ++ all_errors

      cond do
        final_errors != [] ->
          handle_error({:error, final_errors}, module, error?)

        true ->
          {:ok, struct_value}
      end
    else
      {:error, errs} when is_list(errs) ->
        handle_error({:error, errs}, module, error?)

      {:error, err} ->
        handle_error({:error, [err]}, module, error?)
    end
  end

  defp read_metadata(module) do
    {module.__guarded_information__(), module.__guarded_fields__()}
  end

  defp section_options_from(info) do
    Map.get(info, :options, %{authorized_fields: false})
  end

  defp normalize_keys(attrs, dynamic_field_names) when is_map(attrs) do
    case Map.keys(attrs) |> List.first() do
      nil -> {:ok, attrs}
      _ -> {:ok, Parser.convert_to_atom_map(attrs, dynamic_field_names)}
    end
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
    Enum.reduce(fields_meta, attrs, fn meta, acc ->
      case meta.auto do
        nil ->
          acc

        {mod, fun} ->
          if type == :edit and not is_nil(Map.get(acc, meta.name)) do
            acc
          else
            Map.put(acc, meta.name, apply(mod, fun, []))
          end

        {mod, fun, arg} when is_list(arg) ->
          if type == :edit and not is_nil(Map.get(acc, meta.name)) do
            acc
          else
            Map.put(acc, meta.name, apply(mod, fun, arg))
          end

        {mod, fun, arg} ->
          if type == :edit and not is_nil(Map.get(acc, meta.name)) do
            acc
          else
            Map.put(acc, meta.name, apply(mod, fun, [arg]))
          end
      end
    end)
  end

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

  defp get_domain_field(field, attrs) do
    field
    |> String.trim()
    |> String.split(".", trim: true)
    |> Enum.map(&String.to_atom/1)
    |> then(&get_in(attrs, &1))
  end

  defp build_sub_fields(attrs, fields_meta, parent_module, full_attrs, parent_path) do
    by_name =
      Enum.reduce(fields_meta, %{}, fn f, acc ->
        Map.update(acc, f.name, [f], &(&1 ++ [f]))
      end)

    embedded =
      attrs
      |> Map.keys()
      |> Enum.flat_map(fn k ->
        case Map.get(by_name, k) do
          nil ->
            []

          [first | _] ->
            embedded? =
              first.kind in [:sub_field, :conditional_field] or
                not is_nil(Map.get(first, :struct)) or
                (not is_nil(Map.get(first, :structs)) and Map.get(first, :structs) != false)

            if embedded?, do: [first], else: []
        end
      end)

    Enum.reduce(embedded, {:ok, %{}, []}, fn meta, {:ok, ok_acc, err_acc} ->
      case Map.get(attrs, meta.name) do
        nil ->
          {:ok, ok_acc, err_acc}

        value ->
          case run_pre_validator(meta, value, parent_module) do
            {:ok, validated} ->
              if meta.kind == :conditional_field do
                dispatch(
                  meta,
                  validated,
                  parent_module,
                  ok_acc,
                  err_acc,
                  full_attrs,
                  parent_path
                )
              else
                case pre_derive(meta, validated) do
                  {:ok, sanitized} ->
                    dispatch(
                      meta,
                      sanitized,
                      parent_module,
                      ok_acc,
                      err_acc,
                      full_attrs,
                      parent_path
                    )

                  {:error, errs} ->
                    {:ok, ok_acc, err_acc ++ [%{field: meta.name, errors: errs}]}
                end
              end

            {:error, err} ->
              {:ok, ok_acc, err_acc ++ [%{field: meta.name, errors: err}]}
          end
      end
    end)
  end

  defp run_pre_validator(%{validator: {mod, fun}, name: name}, value, _parent)
       when is_atom(mod) and is_atom(fun) do
    apply_validator(mod, fun, name, value)
  end

  defp run_pre_validator(%{struct: m} = meta, value, _parent)
       when is_atom(m) and not is_nil(m) do
    apply_caller_validator(m, meta.name, value)
  end

  defp run_pre_validator(%{structs: m} = meta, value, _parent)
       when is_atom(m) and m not in [nil, true, false] do
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

  defp pre_derive(%{__derive_ops__: ops, name: name}, value)
       when not is_nil(ops) do
    input = %{field: name, derive_ops: ops}

    case Derive.derive({:ok, %{name => value}, [input]}) do
      {:ok, %{^name => sanitized}} -> {:ok, sanitized}
      {:error, errs} -> {:error, errs}
    end
  end

  defp pre_derive(_meta, value), do: {:ok, value}

  defp dispatch(meta, value, parent_module, ok_acc, err_acc, full_attrs, parent_path) do
    cond do
      meta.kind == :conditional_field ->
        dispatch_conditional(meta, value, parent_module, ok_acc, err_acc, full_attrs, parent_path)

      is_atom(meta.structs) and meta.structs not in [nil, true, false] and is_list(value) ->
        build_list(meta.structs, meta.name, value, ok_acc, err_acc, full_attrs, parent_path)

      is_atom(meta.struct) and not is_nil(meta.struct) and is_map(value) ->
        build_single(meta.struct, meta.name, value, ok_acc, err_acc, full_attrs, parent_path)

      meta.kind == :sub_field and Map.get(meta, :list?) == true and is_list(value) ->
        submodule = Module.concat(parent_module, atom_to_module(meta.name))
        build_list(submodule, meta.name, value, ok_acc, err_acc, full_attrs, parent_path)

      meta.kind == :sub_field and is_map(value) ->
        submodule = Module.concat(parent_module, atom_to_module(meta.name))
        build_single(submodule, meta.name, value, ok_acc, err_acc, full_attrs, parent_path)

      true ->
        {:ok, ok_acc, err_acc}
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
          final_errors =
            if Map.get(meta, :priority) == true and child_errors != [] do
              [List.first(child_errors)]
            else
              child_errors
            end

          {:ok, ok_acc,
           err_acc ++
             [%{field: meta.name, errors: final_errors, action: :conditionals}]}
      end
    end
  end

  defp try_conditional_children(value, children, parent_meta, parent_module, full_attrs, path) do
    Enum.reduce_while(children, {:error, []}, fn child, {:error, errs} ->
      case try_conditional_child(child, value, parent_meta, parent_module, full_attrs, path) do
        {:ok, _} = ok ->
          {:halt, ok}

        {:error, e} ->
          hinted = hint_error(e, child)
          new_errs = if is_list(hinted), do: errs ++ hinted, else: errs ++ [hinted]
          {:cont, {:error, new_errs}}
      end
    end)
  end

  defp hint_error(err, %{hint: nil}), do: err

  defp hint_error(errs, %{hint: h}) when is_list(errs) and is_binary(h),
    do: Enum.map(errs, &Map.put(&1, :__hint__, h))

  defp hint_error(err, %{hint: h}) when is_map(err) and is_binary(h),
    do: Map.put(err, :__hint__, h)

  defp hint_error(err, _), do: err

  defp try_conditional_child(%{kind: :field} = child, value, _parent, _module, _full, _path) do
    case run_child_validator(child, value) do
      {:ok, validated} ->
        cond do
          is_atom(Map.get(child, :struct)) and not is_nil(Map.get(child, :struct)) ->
            if is_map(validated) do
              child.struct.builder(validated)
            else
              {:error,
               [
                 %{
                   field: Map.get(child, :name, :__root__),
                   action: :bad_parameters,
                   message: translated_message(:builder)
                 }
               ]}
            end

          is_atom(Map.get(child, :structs)) and
              Map.get(child, :structs) not in [nil, true, false] ->
            if is_list(validated) do
              mod = child.structs

              built =
                Enum.flat_map(validated, fn
                  item when is_list(item) ->
                    Enum.map(item, fn v -> mod.builder(v) end)

                  item ->
                    [mod.builder(item)]
                end)

              case Enum.find(built, &(elem(&1, 0) == :error)) do
                nil -> {:ok, Enum.map(built, &elem(&1, 1))}
                {:error, errs} -> {:error, errs}
              end
            else
              {:error,
               %{
                 message: translated_message(:list_builder_type),
                 field: child.name,
                 action: :type
               }}
            end

          true ->
            case run_child_derive(child, validated) do
              {:ok, sanitized} -> {:ok, sanitized}
              {:error, errs} -> {:error, errs}
            end
        end

      {:error, err} ->
        {:error, err}
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
      sub_index = Map.get(child, :sub_field_index)

      submodule_name =
        if sub_index do
          "#{parent.name}#{sub_index}" |> String.to_atom() |> atom_to_module()
        else
          atom_to_module(name)
        end

      submodule = Module.concat(parent_module, submodule_name)
      nested_input_for = fn v -> {:__nested__, v, full_attrs, path, :add} end

      cond do
        Map.get(child, :list?) == true and is_list(sanitized) ->
          built =
            Enum.flat_map(sanitized, fn
              item when is_map(item) ->
                [submodule.builder(nested_input_for.(item))]

              item when is_list(item) ->
                Enum.map(item, fn v -> submodule.builder(nested_input_for.(v)) end)

              _ ->
                [
                  {:error,
                   [
                     %{
                       field: Map.get(child, :name, :__root__),
                       action: :bad_parameters,
                       message: translated_message(:builder)
                     }
                   ]}
                ]
            end)

          case Enum.find(built, &(elem(&1, 0) == :error)) do
            nil -> {:ok, Enum.map(built, &elem(&1, 1))}
            {:error, errs} -> {:error, errs}
          end

        Map.get(child, :list?) == true ->
          {:error,
           %{
             message: translated_message(:list_builder_type),
             field: name,
             action: :type
           }}

        is_map(sanitized) ->
          submodule.builder(nested_input_for.(sanitized))

        true ->
          {:error, [%{field: :__root__, action: :bad_parameters, message: translated_message(:builder)}]}
      end
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
    children = child.children
    is_list_cond = Map.get(child, :structs) == true or Map.get(child, :list?) == true

    cond do
      is_list_cond and is_list(value) ->
        results =
          Enum.map(value, fn item ->
            try_conditional_children(item, children, child, parent_module, full_attrs, path)
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

      is_list_cond ->
        {:error,
         %{
           field: child.name,
           message: translated_message(:list_builder_type),
           action: :type
         }}

      true ->
        case try_conditional_children(value, children, child, parent_module, full_attrs, path) do
          {:ok, _} = ok -> ok
          {:error, errs} -> {:error, %{field: child.name, errors: errs, action: :conditionals}}
        end
    end
  end

  defp run_child_derive(%{derive: nil}, value), do: {:ok, value}

  defp run_child_derive(%{name: name} = child, value) do
    ops = Map.get(child, :__derive_ops__)
    str = Map.get(child, :derive)

    cond do
      is_nil(ops) and is_nil(str) ->
        {:ok, value}

      true ->
        input = %{field: name, derive: str, derive_ops: ops}

        case Derive.derive({:ok, %{name => value}, [input]}) do
          {:ok, %{^name => sanitized}} -> {:ok, sanitized}
          {:error, errs} -> {:error, errs}
        end
    end
  end

  defp run_child_derive(_child, value), do: {:ok, value}

  defp run_child_validator(%{validator: {mod, fun}, name: name}, value)
       when is_atom(mod) and is_atom(fun) do
    case apply(mod, fun, [name, value]) do
      {:ok, _key, new_value} -> {:ok, new_value}
      {:error, key, message} -> {:error, %{field: key, message: message, action: :validator}}
    end
  end

  defp run_child_validator(_child, value), do: {:ok, value}

  defp collect_list_conditional_results(results, meta, ok_acc, err_acc) do
    {oks, errs} =
      Enum.reduce(results, {[], []}, fn
        {:ok, val}, {oks, errs} -> {oks ++ [val], errs}
        {:error, errors}, {oks, errs} -> {oks, errs ++ errors}
      end)

    deduped = Enum.uniq(errs)

    final_errs =
      if Map.get(meta, :priority) == true and deduped != [] do
        [List.first(deduped)]
      else
        deduped
      end

    cond do
      final_errs != [] ->
        {:ok, ok_acc, err_acc ++ [%{field: meta.name, errors: final_errs, action: :conditionals}]}

      true ->
        {:ok, Map.put(ok_acc, meta.name, oks), err_acc}
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

    case Enum.find(built, &(elem(&1, 0) == :error)) do
      nil ->
        {:ok, Map.put(ok_acc, field_name, Enum.map(built, &elem(&1, 1))), err_acc}

      {:error, errs} ->
        {:ok, ok_acc, err_acc ++ [%{field: field_name, errors: errs}]}
    end
  end

  # Push `module` onto the process-dict current-module stack so derive
  # extension lookups inside this build resolve against it. We only push
  # when `module` has a per-module `derive_extensions:` opt — otherwise
  # we inherit the caller's pdict (this is how sub_field auto-generated
  # submodules pick up the root user module's opt).
  defp with_module_context(module, fun) do
    case module.__guarded_derive_extensions_opt__() do
      nil ->
        fun.()

      _opt ->
        previous = Process.get(:guarded_struct_current_module)
        Process.put(:guarded_struct_current_module, module)

        try do
          fun.()
        after
          case previous do
            nil -> Process.delete(:guarded_struct_current_module)
            prev -> Process.put(:guarded_struct_current_module, prev)
          end
        end
    end
  end

  defp run_per_field_validators_collect(attrs, _fields_meta, module) do
    Enum.reduce(attrs, {%{}, []}, fn {key, value}, {ok_acc, err_acc} ->
      meta = module.__field_meta__(key)

      cond do
        embedded?(meta) ->
          {Map.put(ok_acc, key, value), err_acc}

        true ->
          case run_field_validator(meta, key, value, module) do
            {:ok, new_value} ->
              {Map.put(ok_acc, key, new_value), err_acc}

            {:error, message} ->
              {ok_acc, err_acc ++ [%{field: key, message: message, action: :validator}]}
          end
      end
    end)
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

  defp run_main_validator(attrs, module) do
    if module.__guarded_has_main_validator__() do
      case module.main_validator(attrs) do
        {:ok, value} -> {:ok, value}
        {:error, errs} when is_list(errs) -> {:error, errs}
        {:error, err} -> {:error, [err]}
        _ -> {:ok, attrs}
      end
    else
      {:ok, attrs}
    end
  end

  defp run_derives(value, fields_meta) do
    derive_inputs =
      Enum.flat_map(fields_meta, fn f ->
        ops = Map.get(f, :__derive_ops__)
        str = Map.get(f, :derive)

        cond do
          is_nil(ops) and is_nil(str) -> []
          true -> [%{field: f.name, derive: str, derive_ops: ops}]
        end
      end)

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
        %{kind: :sub_field} -> %{k => all_keys(Module.concat(module, atom_to_module(k)))}
        _ -> k
      end
    end)
  end

  @doc false
  def all_enforce_keys(module) do
    Enum.flat_map(module.__information__().enforce_keys, fn k ->
      case module.__field_meta__(k) do
        %{kind: :sub_field} -> [%{k => all_keys(Module.concat(module, atom_to_module(k)))}]
        _ -> [k]
      end
    end)
  end

  defp atom_to_module(field_atom) do
    field_atom |> Atom.to_string() |> Macro.camelize() |> String.to_atom()
  end
end
