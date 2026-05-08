defmodule GuardedStruct.Runtime do
  @moduledoc false

  # Runtime build pipeline for the Spark-based GuardedStruct rewrite.
  # Mirrors the legacy `GuardedStruct.builder/4` step order (see
  # `REDESIGN.md` §12 and the legacy `lib/guarded_struct.ex:1582-1629`).

  alias GuardedStruct.Derive
  alias GuardedStruct.Derive.Parser
  alias GuardedStruct.Derive.ValidationDerive

  @spec build(module(), map() | struct() | tuple(), boolean()) ::
          {:ok, struct()} | {:error, any()}
  def build(module, attrs, error?)

  def build(module, attrs, error?) when is_struct(attrs) do
    build(module, Map.from_struct(attrs), error?)
  end

  def build(module, attrs, error?) when is_map(attrs) do
    do_build(module, attrs, attrs, :add, error?)
  end

  def build(module, {key, attrs}, error?) when is_atom(key) or is_list(key) do
    do_build_with_key(module, key, attrs, :add, error?)
  end

  def build(module, {key, attrs, type}, error?)
      when (is_atom(key) or is_list(key)) and type in [:add, :edit] do
    do_build_with_key(module, key, attrs, type, error?)
  end

  # Internal nested-build call: pass FULL root attrs so `root::path` core keys
  # resolve correctly inside sub_fields. `path` is the list of field names
  # walked from the root to reach this scope's local attrs.
  def build(module, {:__nested__, local_attrs, full_attrs, path, type}, error?) do
    do_build(module, local_attrs, full_attrs, type, error?, path)
  end

  def build(_module, _attrs, _error?) do
    {:error, %{message: "Your input must be a map or list of maps", action: :bad_parameters}}
  end

  defp do_build_with_key(module, :root, attrs, type, error?),
    do: do_build(module, attrs, attrs, type, error?)

  defp do_build_with_key(module, [:root], attrs, type, error?),
    do: do_build(module, attrs, attrs, type, error?)

  defp do_build_with_key(module, key, attrs, type, error?) when is_list(key) do
    case get_in(attrs, key) do
      sub when is_map(sub) -> do_build(module, sub, attrs, type, error?)
      _ -> {:error, %{message: "Bad path", action: :bad_parameters}}
    end
  end

  defp do_build_with_key(module, key, attrs, type, error?) when is_atom(key) do
    case Map.get(attrs, key) do
      sub when is_map(sub) -> do_build(module, sub, attrs, type, error?)
      _ -> {:error, %{message: "Bad path", action: :bad_parameters}}
    end
  end

  # Main build pipeline. `attrs` is the current scope (sub-tree), `full_attrs`
  # is the original root attrs — needed for `root::` core-key paths. `path`
  # is the list of field names from root to here (for sub_field dispatch).
  #
  # Non-map input is normalized to an empty map — legacy `before_revaluation`
  # at `lib/guarded_struct.ex:1640` converts non-map input into a stub map and
  # the subsequent `required_fields` check produces the actual error.
  defp do_build(module, attrs, full_attrs, type, error?, path \\ [])

  defp do_build(module, attrs, full_attrs, type, error?, path) when not is_map(attrs) do
    do_build(module, %{}, full_attrs, type, error?, path)
  end

  defp do_build(module, attrs, full_attrs, type, error?, path) when is_map(attrs) do
    info = module.__information__()
    fields_meta = module.__fields__()
    section_opts = section_options(module)

    keys = info.keys
    enforce_keys = info.enforce_keys

    full_attrs_atomized = Parser.convert_to_atom_map(full_attrs)

    with {:ok, normalized} <- normalize_keys(attrs),
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

      # Continue through main_validator and derive even when sub_errors exist,
      # so any field-level derive failures (e.g. on `last_activity`) accumulate
      # alongside sub-field errors. Legacy aggregates ALL errors before
      # surfacing — see `validation_errors_aggregator` at
      # `lib/guarded_struct.ex:2646`.
      {derive_errors, struct_value} =
        case run_main_validator(validator_attrs, module) do
          {:ok, after_main} ->
            sv = struct(module, Map.merge(after_main, sub_field_data))

            case run_derives(sv, fields_meta) do
              {:ok, derived} -> {[], derived}
              {:error, errs} -> {errs, sv}
            end

          {:error, errs} when is_list(errs) ->
            {errs, struct(module, Map.merge(validator_attrs, sub_field_data))}

          {:error, err} ->
            {[err], struct(module, Map.merge(validator_attrs, sub_field_data))}
        end

      # Order: derive errors first, then sub-field errors. This matches the
      # legacy aggregator output order — see the test "nested macro field"
      # in test/global_test.exs which pattern-matches on this exact ordering.
      final_errors = derive_errors ++ all_errors

      cond do
        final_errors != [] ->
          handle_error({:error, final_errors}, module, error?)

        true ->
          {:ok, struct_value}
      end
    else
      # `authorized_fields` produces a single error map at this level too.
      {:error, %{action: :authorized_fields}} = err ->
        handle_error(err, module, error?)

      {:error, %{action: :required_fields}} = err ->
        handle_error(err, module, error?)

      {:error, errs} when is_list(errs) ->
        handle_error({:error, errs}, module, error?)

      {:error, _} = err ->
        handle_error(err, module, error?)
    end
  end

  defp section_options(module) do
    info = module.__information__()
    Map.get(info, :options, %{authorized_fields: false})
  end

  defp normalize_keys(attrs) when is_map(attrs) do
    case Map.keys(attrs) |> List.first() do
      nil -> {:ok, attrs}
      _ -> {:ok, Parser.convert_to_atom_map(attrs)}
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
       %{
         message: "Unauthorized keys are present in the sent data.",
         fields: extras,
         action: :authorized_fields
       }}
    end
  end

  defp check_enforce_keys(_attrs, []), do: :ok

  defp check_enforce_keys(attrs, enforce_keys) do
    missing = Enum.reject(enforce_keys, &Map.has_key?(attrs, &1))

    if missing == [] do
      :ok
    else
      {:error,
       %{
         message: "Please submit required fields.",
         fields: missing,
         action: :required_fields
       }}
    end
  end

  # Apply `auto: {Mod, :fn}` / `auto: {Mod, :fn, default}` at compile-time-known
  # call sites. In `:edit` mode, preserve user-supplied values.
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

  # `on: "root::path"` or `"sibling::path"` — if the dependent path is missing
  # but the field's value IS provided, raise a :dependent_keys error.
  defp check_on(attrs, fields_meta, full_attrs) do
    errors =
      fields_meta
      # Legacy iterates :gs_core_keys in reverse-accumulation order; tests
      # pattern-match against that ordering.
      |> Enum.reverse()
      |> Enum.flat_map(fn
        %{on: nil} -> []
        %{on: pattern, name: name} -> [check_on_pattern(name, pattern, attrs, full_attrs)]
        _ -> []
      end)
      |> Enum.reject(&is_nil/1)

    if errors == [], do: {:ok, attrs}, else: {:error, errors}
  end

  defp check_on_pattern(field_name, pattern, attrs, full_attrs) do
    [head | rest] = path = Parser.parse_core_keys_pattern(pattern)
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
          message:
            "The required dependency for field #{field_name} has not been submitted.\n" <>
              "You must have field #{List.last(path)} in your input\n",
          field: field_name,
          action: :dependent_keys
        }
      end
    end
  end

  # `from: "root::path"` — copy a value from another path (root or local) into
  # this field if the field isn't already set in attrs.
  defp apply_from(attrs, fields_meta, full_attrs) do
    Enum.reduce(fields_meta, attrs, fn
      %{from: nil}, acc ->
        acc

      %{from: pattern, name: name}, acc ->
        [head | rest] = path = Parser.parse_core_keys_pattern(pattern)

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

  # `domain: "!path=Type[...]::?path=Type[...]"` — input-shape constraints.
  # Reuses the legacy parser at `lib/guarded_struct.ex:2475`.
  defp check_domain(full_attrs, attrs, fields_meta) do
    errors =
      fields_meta
      |> Enum.flat_map(fn
        %{domain: nil} -> []
        %{domain: pattern, name: name} -> parse_domain(pattern, name, full_attrs, attrs)
        _ -> []
      end)
      |> List.flatten()

    if errors == [], do: {:ok, attrs}, else: {:error, errors}
  end

  defp parse_domain(pattern, key, full_attrs, attrs) do
    case Map.get(full_attrs, key) || Map.get(attrs, key) do
      nil ->
        []

      _ ->
        pattern
        |> String.trim()
        |> String.split("::", trim: true)
        |> Enum.map(&String.split(&1, "=", trim: true))
        |> Enum.map(fn
          ["!" <> field, p] -> domain_field_status(field, full_attrs, p, key, :error)
          ["?" <> field, p] -> domain_field_status(field, full_attrs, p, key)
        end)
        |> Enum.reject(&is_nil/1)
    end
  end

  defp domain_field_status(field, attrs, converted_pattern, key, force \\ nil) do
    domain_field = get_domain_field(field, attrs)
    converted = converted_domain_pattern(converted_pattern)

    cond do
      not is_nil(domain_field) ->
        case ValidationDerive.validate(converted, domain_field, key) do
          data when is_tuple(data) and elem(data, 0) == :error ->
            %{
              message: "Based on field #{key} input you have to send authorized data",
              field_path: field,
              field: key,
              action: :domain_parameters
            }

          _ ->
            nil
        end

      is_nil(force) ->
        nil

      true ->
        %{
          message:
            "Based on field #{key} input you have to send authorized data and required key",
          field_path: field,
          field: key,
          action: :domain_parameters
        }
    end
  end

  defp converted_domain_pattern(pattern) do
    case pattern do
      "Tuple" <> list ->
        {:enum, "Tuple[#{re_structure(list, "string")}]"}

      "Map" <> list ->
        {:enum, "Map[#{re_structure(list, "string")}]"}

      "Equal" <> data ->
        {:equal, data |> String.replace(["[", "]"], "") |> String.replace(">>", "::")}

      "Either" <> list ->
        converted =
          list
          |> String.replace("enum>>", "enum=")
          |> String.replace(">>", "::")
          |> then(&Parser.convert_parameters("parsed_string", Code.string_to_quoted!(&1)))

        %{either: converted["parsed_string"]}

      "Custom" <> list ->
        {:custom, list}

      data ->
        {:enum, re_structure(data)}
    end
  end

  defp re_structure(data) do
    data |> String.split(",", trim: true) |> Enum.map(&String.trim/1) |> Enum.join("::")
  end

  defp re_structure(data, "string") do
    {converted, []} = Code.eval_string(data)
    Enum.reduce(converted, "", fn item, acc -> acc <> "#{Macro.to_string(item)}::" end)
  end

  defp get_domain_field(field, attrs) do
    field
    |> String.trim()
    |> String.split(".", trim: true)
    |> Enum.map(&String.to_atom/1)
    |> then(&get_in(attrs, &1))
  end

  # Sub-field / struct: / structs: / conditional_field dispatch. Iterate by
  # INPUT-attrs order so the resulting error list reflects the user's input
  # ordering — this is what existing tests pattern-match.
  defp build_sub_fields(attrs, fields_meta, parent_module, full_attrs, parent_path) do
    # Group fields_meta by name — conditional_field children share a name with
    # the parent. We pick the FIRST entry per name from fields_meta when
    # iterating, but keep the full list for conditional dispatch.
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
              # Skip pre_derive for conditional_field — dispatch_conditional
              # handles its own derive and wraps the error with the
              # `action: :conditionals` marker.
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
    if Code.ensure_loaded?(mod) and function_exported?(mod, :validator, 2) do
      case apply(mod, :validator, [field, value]) do
        {:ok, _key, new_value} -> {:ok, new_value}
        {:error, key, message} -> {:error, %{field: key, message: message, action: :validator}}
        _ -> {:ok, value}
      end
    else
      {:ok, value}
    end
  end

  defp pre_derive(%{derive: nil}, value), do: {:ok, value}

  defp pre_derive(%{derive: str, name: name}, value) when is_binary(str) do
    case Derive.derive({:ok, %{name => value}, [%{field: name, derive: str}]}) do
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

  # Try each child of a conditional_field in order. First child whose
  # validator (or natural shape match) returns `:ok` wins. Errors aggregate
  # under the conditional's name with `action: :conditionals` and per-child
  # `__hint__` markers.
  defp dispatch_conditional(meta, value, parent_module, ok_acc, err_acc, full_attrs, parent_path) do
    children = meta.children
    new_path = parent_path ++ [meta.name]

    # Apply the conditional_field's OWN derive (e.g. `validate(not_flatten_empty_item)`)
    # to the raw input before trying any child. If it fails, the error is the
    # only one reported under this conditional. Legacy parity at
    # `lib/guarded_struct.ex:2477-2493`.
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
          # `struct: SomeMod` — value MUST be a map; otherwise this branch
          # doesn't match.
          is_atom(Map.get(child, :struct)) and not is_nil(Map.get(child, :struct)) ->
            if is_map(validated) do
              child.struct.builder(validated)
            else
              {:error,
               %{
                 message: "Your input must be a map or list of maps",
                 action: :bad_parameters
               }}
            end

          # `structs: SomeMod` — value MUST be a list. Nested list items are
          # treated by iterating the inner list (legacy semantics at
          # `lib/guarded_struct.ex:2308-2314`).
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
                 message: "Your input must be a list of items",
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
          # Legacy semantics for list items (`lib/guarded_struct.ex:2308`):
          #   * map item → submodule.builder(item)
          #   * list item → iterate inner list, build each (skip empties)
          #   * other → builder error
          built =
            Enum.flat_map(sanitized, fn
              item when is_map(item) ->
                [submodule.builder(nested_input_for.(item))]

              item when is_list(item) ->
                Enum.map(item, fn v -> submodule.builder(nested_input_for.(v)) end)

              _ ->
                [
                  {:error,
                   %{
                     message: "Your input must be a map or list of maps",
                     action: :bad_parameters
                   }}
                ]
            end)

          case Enum.find(built, &(elem(&1, 0) == :error)) do
            nil -> {:ok, Enum.map(built, &elem(&1, 1))}
            {:error, errs} -> {:error, errs}
          end

        Map.get(child, :list?) == true ->
          {:error,
           %{
             message: "Your input must be a list of items",
             field: name,
             action: :type
           }}

        is_map(sanitized) ->
          submodule.builder(nested_input_for.(sanitized))

        true ->
          {:error,
           %{message: "Your input must be a map or list of maps", action: :bad_parameters}}
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
    # A nested conditional_field can have `structs: true` — meaning the matched
    # value must be a list, and each element is tried against the inner
    # children individually (mirrors dispatch_conditional's list mode).
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

            {:error,
             %{field: child.name, errors: collected, action: :conditionals}}
        end

      is_list_cond ->
        {:error,
         %{
           field: child.name,
           message: "Your input must be a list of items",
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

  defp run_child_derive(%{derive: str, name: name}, value) when is_binary(str) do
    case Derive.derive({:ok, %{name => value}, [%{field: name, derive: str}]}) do
      {:ok, %{^name => sanitized}} -> {:ok, sanitized}
      {:error, errs} -> {:error, errs}
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

    # Dedupe identical errors across list elements (legacy `Enum.uniq` at
    # `lib/guarded_struct.ex:2615`). Preserves first-seen order so the result
    # is element-1's errors in child order, then any UNIQUE errors from
    # subsequent elements.
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

    case module.builder(nested_input) do
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
        module.builder({:__nested__, item, full_attrs, new_path, :add})
      end)

    case Enum.find(built, &(elem(&1, 0) == :error)) do
      nil ->
        {:ok, Map.put(ok_acc, field_name, Enum.map(built, &elem(&1, 1))), err_acc}

      {:error, errs} ->
        {:ok, ok_acc, err_acc ++ [%{field: field_name, errors: errs}]}
    end
  end

  defp run_per_field_validators_collect(attrs, fields_meta, module) do
    Enum.reduce(attrs, {%{}, []}, fn {key, value}, {ok_acc, err_acc} ->
      meta = Enum.find(fields_meta, fn f -> f.name == key end)

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
    if function_exported?(module, :validator, 2) do
      case apply(module, :validator, [key, value]) do
        {:ok, _key, new_value} -> {:ok, new_value}
        {:error, _key, message} -> {:error, message}
        _ -> {:ok, value}
      end
    else
      {:ok, value}
    end
  end

  defp run_main_validator(attrs, module) do
    cond do
      function_exported?(module, :main_validator, 1) ->
        case apply(module, :main_validator, [attrs]) do
          {:ok, value} -> {:ok, value}
          {:error, errs} when is_list(errs) -> {:error, errs}
          {:error, err} -> {:error, [err]}
          _ -> {:ok, attrs}
        end

      true ->
        {:ok, attrs}
    end
  end

  defp run_derives(struct_value, fields_meta) do
    derive_inputs =
      Enum.flat_map(fields_meta, fn f ->
        case f.derive do
          nil -> []
          str when is_binary(str) -> [%{field: f.name, derive: str}]
          _ -> []
        end
      end)

    if derive_inputs == [] do
      {:ok, struct_value}
    else
      data_map = Map.from_struct(struct_value)

      case Derive.derive({:ok, data_map, derive_inputs}) do
        {:ok, processed} -> {:ok, struct(struct_value.__struct__, processed)}
        {:error, errors} -> {:error, errors}
      end
    end
  end

  defp handle_error({:error, errs} = result, module, true) do
    error_module = Module.concat(module, Error)

    if Code.ensure_loaded?(error_module) do
      raise error_module, errors: errs, term: nil
    else
      result
    end
  end

  defp handle_error(result, _module, _error?), do: result

  # Public helpers for keys(:all) / enforce_keys(:all).
  @doc false
  def all_keys(module) do
    info = module.__information__()
    fields_meta = module.__fields__()

    Enum.map(info.keys, fn k ->
      meta = Enum.find(fields_meta, fn f -> f.name == k end)

      case meta do
        %{kind: :sub_field} ->
          submodule = Module.concat(module, atom_to_module(k))

          if Code.ensure_loaded?(submodule) and function_exported?(submodule, :__information__, 0),
            do: %{k => all_keys(submodule)},
            else: k

        _ ->
          k
      end
    end)
  end

  @doc false
  def all_enforce_keys(module) do
    info = module.__information__()
    fields_meta = module.__fields__()

    Enum.flat_map(info.enforce_keys, fn k ->
      meta = Enum.find(fields_meta, fn f -> f.name == k end)

      case meta do
        %{kind: :sub_field} ->
          submodule = Module.concat(module, atom_to_module(k))

          # Legacy: enforce_keys(:all) at the outer level recurses with
          # `:keys` (ALL keys) into sub_fields, not just their enforced ones.
          # See `lib/guarded_struct.ex:2072` show_nested_keys default arg.
          nested =
            if Code.ensure_loaded?(submodule) and
                 function_exported?(submodule, :__information__, 0),
               do: all_keys(submodule),
               else: []

          [%{k => nested}]

        _ ->
          [k]
      end
    end)
  end

  defp atom_to_module(field_atom) do
    field_atom |> Atom.to_string() |> Macro.camelize() |> String.to_atom()
  end
end
