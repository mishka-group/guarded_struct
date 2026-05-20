defmodule GuardedStruct.Info do
  @moduledoc """
  Runtime introspection of guardedstruct DSL state.

  Built on `Spark.InfoGenerator`, which auto-generates accessors for every
  section option in the DSL (e.g. `guardedstruct_enforce!/1`,
  `guardedstruct_json!/1`). On top of those, this module exposes ergonomic
  helpers so callers don't have to walk `__fields__/0` maps themselves.

  ## Helper categories

  * **Field-level lookups** — `field_kind/2`, `field_default/2`,
    `field_derives/2`, `field_validator/2`, `field_auto/2`, `enforce?/2`,
    `virtual?/2`, `dynamic?/2`
  * **Collections by kind** — `sub_fields/1`, `virtual_fields/1`,
    `dynamic_fields/1`, `conditional_fields/1`, `conditional_keys/1`,
    `pattern_keyed?/1`
  * **Section-option shorthands** — `enforce?/1`, `opaque?/1`,
    `authorized_fields?/1`, `json?/1`, `error?/1`
  * **Navigation** — `sub_module/2`, `conditional_children/2`

  ## Example

      defmodule MyApp.User do
        use GuardedStruct
        guardedstruct enforce: true do
          field :name, String.t()
          virtual_field :password_confirm, String.t()
          sub_field :address, struct() do
            field :city, String.t()
          end
        end
      end

      GuardedStruct.Info.fields(MyApp.User)            #=> [:name, :password_confirm, :address]
      GuardedStruct.Info.virtual_fields(MyApp.User)    #=> [:password_confirm]
      GuardedStruct.Info.sub_fields(MyApp.User)        #=> [:address]
      GuardedStruct.Info.field_kind(MyApp.User, :name) #=> :field
      GuardedStruct.Info.enforce?(MyApp.User, :name)   #=> true
      GuardedStruct.Info.sub_module(MyApp.User, :address) #=> MyApp.User.Address
  """

  alias GuardedStruct.Transformers.Codegen

  use Spark.InfoGenerator,
    extension: GuardedStruct.Dsl,
    sections: [:guardedstruct]

  # ────────────────────────────────────────────────────────────────────────
  # Existing API
  # ────────────────────────────────────────────────────────────────────────

  @doc """
  Return the user-declared field, sub_field, virtual_field, dynamic_field
  and conditional_field names in declaration order. Works on both the
  top-level module and any generated sub_field submodule.
  """
  def fields(module) do
    module.__fields__() |> Enum.map(& &1.name) |> Enum.uniq()
  end

  @doc "Return the list of enforced field names."
  def enforce_keys(module), do: module.enforce_keys()

  @doc """
  Return the runtime field metadata — same shape as the generated module's
  `__fields__/0`.
  """
  def fields_meta(module), do: module.__fields__()

  @doc "Return the field metadata for a single name, or `nil` if absent."
  def field(module, name) when is_atom(name), do: module.__field_meta__(name)

  @doc "True if the field exists on this module (or any sub_field cascade)."
  def field?(module, name) when is_atom(name) do
    name in module.keys() or not is_nil(module.__field_meta__(name))
  end

  # ────────────────────────────────────────────────────────────────────────
  # Field-level lookups
  # ────────────────────────────────────────────────────────────────────────

  @doc """
  Return the kind of a field: `:field`, `:sub_field`, `:virtual_field`,
  `:dynamic_field`, `:conditional_field`, or `:pattern_field`. `nil` if
  the field doesn't exist.
  """
  def field_kind(module, name) when is_atom(name) do
    case field(module, name) do
      nil -> nil
      meta -> meta.kind
    end
  end

  @doc "Return the field's `default:`, or `nil` if none or field absent."
  def field_default(module, name) when is_atom(name) do
    case field(module, name) do
      nil -> nil
      meta -> Map.get(meta, :default)
    end
  end

  @doc """
  Return the original derive string for a field (the canonical
  `derives:` option, falling back to the legacy `derive:`).
  """
  def field_derives(module, name) when is_atom(name) do
    case field(module, name) do
      nil -> nil
      meta -> Map.get(meta, :derive)
    end
  end

  @doc """
  Return the `{Mod, fun}` per-field validator MFA, or `nil` if none.
  """
  def field_validator(module, name) when is_atom(name) do
    case field(module, name) do
      nil -> nil
      meta -> Map.get(meta, :validator)
    end
  end

  @doc "Return the `{Mod, fun}` `auto:` MFA, or `nil` if none."
  def field_auto(module, name) when is_atom(name) do
    case field(module, name) do
      nil -> nil
      meta -> Map.get(meta, :auto)
    end
  end

  @doc "True if the field is enforced (member of `enforce_keys/0`)."
  def enforce?(module, name) when is_atom(name) do
    name in module.enforce_keys()
  end

  @doc "True if `name` is a `virtual_field`."
  def virtual?(module, name) when is_atom(name), do: field_kind(module, name) == :virtual_field

  @doc "True if `name` is a `dynamic_field`."
  def dynamic?(module, name) when is_atom(name), do: field_kind(module, name) == :dynamic_field

  # ────────────────────────────────────────────────────────────────────────
  # Collections by kind
  # ────────────────────────────────────────────────────────────────────────

  @doc "Names of all `sub_field` entries on this module."
  def sub_fields(module), do: names_of_kind(module, :sub_field)

  @doc "Names of all `virtual_field` entries on this module."
  def virtual_fields(module), do: names_of_kind(module, :virtual_field)

  @doc "Names of all `dynamic_field` entries on this module."
  def dynamic_fields(module), do: names_of_kind(module, :dynamic_field)

  @doc "Names of all `conditional_field` entries on this module."
  def conditional_fields(module), do: names_of_kind(module, :conditional_field)

  @doc """
  Names of conditional_field entries, sourced from `__information__/0`'s
  `:conditional_keys` (matches `conditional_fields/1` for normal modules).
  """
  def conditional_keys(module), do: module.__information__().conditional_keys

  @doc """
  True if this module was generated for a pattern-keyed map (its only
  `field` was a regex). Pattern-keyed modules return a map from `builder/1`,
  not a struct.
  """
  def pattern_keyed?(module),
    do: Map.get(module.__information__(), :shape) == :pattern_map

  defp names_of_kind(module, kind) do
    module.__fields__() |> Enum.filter(&(&1.kind == kind)) |> Enum.map(& &1.name)
  end

  # ────────────────────────────────────────────────────────────────────────
  # Section-option shorthands
  # ────────────────────────────────────────────────────────────────────────

  @doc "True if the section was declared with `enforce: true`."
  def enforce?(module), do: guardedstruct_enforce!(module) == true

  @doc "True if the section was declared with `opaque: true`."
  def opaque?(module), do: guardedstruct_opaque!(module) == true

  @doc "True if the section was declared with `authorized_fields: true`."
  def authorized_fields?(module), do: guardedstruct_authorized_fields!(module) == true

  @doc "True if the section was declared with `json: true`."
  def json?(module), do: guardedstruct_json!(module) == true

  @doc "True if the section was declared with `error: true`."
  def error?(module) do
    case guardedstruct_error(module) do
      {:ok, value} -> value == true
      _ -> false
    end
  end

  # ────────────────────────────────────────────────────────────────────────
  # Navigation
  # ────────────────────────────────────────────────────────────────────────

  @doc """
  Return the generated submodule for a `sub_field`, or `nil` if the name
  isn't a sub_field. The submodule path is the parent module concatenated
  with the camelized field name (or with the section's `module:` override).

      Info.sub_module(MyApp.User, :address)
      #=> MyApp.User.Address
  """
  def sub_module(module, name) when is_atom(name) do
    case module.__field_meta__(name) do
      %{kind: :sub_field, child_module: child} -> child
      _ -> nil
    end
  end

  @doc """
  Return the children variants of a `conditional_field`, or `nil` if the
  name isn't a conditional. Each child is a meta map with `:kind`,
  `:name`, and any associated options.
  """
  def conditional_children(module, name) when is_atom(name) do
    case field(module, name) do
      %{kind: :conditional_field, children: children} -> children
      _ -> nil
    end
  end

  # ────────────────────────────────────────────────────────────────────────
  # Everything-in-one-map
  # ────────────────────────────────────────────────────────────────────────

  @doc """
  Return the FULL introspection map for a module: every section option,
  every field's complete metadata, every derived flag, in one structure.

  Works on both the top-level module and any generated sub_field submodule.
  Section-option keys whose values were not declared are present as `nil`,
  so the shape is uniform.

  ## Returned map keys

  * `:module` — the module
  * `:path` — module path from root (empty list for the top-level)
  * `:key` — the field name corresponding to this module (or `:root`)
  * `:shape` — `:struct` or `:pattern_map`
  * `:pattern_keyed?` — convenience boolean
  * `:patterns` — for pattern-map shapes, the list of regex field names
  * `:keys` — struct-bound key names (excludes virtuals)
  * `:enforce_keys` — names of enforced keys
  * `:conditional_keys` — names of conditional_field entries
  * `:options` — map of every section option (with `nil` for absent values)
  * `:fields` — list of per-field meta maps (one per declared entity),
    each augmented with `:enforce?` (membership in enforce_keys) and,
    for sub_field entries, `:sub_module` (the generated submodule)

  ## Example

      Info.describe(MyApp.User)
      #=> %{
      #     module: MyApp.User,
      #     path: [],
      #     key: :root,
      #     shape: :struct,
      #     pattern_keyed?: false,
      #     patterns: [],
      #     keys: [:id, :name, :address, ...],
      #     enforce_keys: [:name, :address],
      #     conditional_keys: [:billing],
      #     options: %{
      #       enforce: true, opaque: false, module: nil, error: false,
      #       authorized_fields: true, main_validator: nil,
      #       validate_derive: nil, sanitize_derive: nil, json: true
      #     },
      #     fields: [
      #       %{name: :id, kind: :field, enforce?: false, ...},
      #       %{name: :address, kind: :sub_field, enforce?: true,
      #         sub_module: MyApp.User.Address, ...},
      #       ...
      #     ]
      #   }
  """
  def describe(module) do
    info = module.__information__()
    enforce_keys = module.enforce_keys()
    raw_fields = module.__fields__()

    fields = Enum.map(raw_fields, &enrich_field(&1, enforce_keys, module))

    %{
      module: module,
      path: info.path,
      key: info.key,
      shape: Map.get(info, :shape, :struct),
      pattern_keyed?: Map.get(info, :shape) == :pattern_map,
      patterns: Map.get(info, :patterns, []),
      keys: info.keys,
      enforce_keys: enforce_keys,
      conditional_keys: info.conditional_keys,
      options: section_options(module, info),
      fields: fields
    }
  end

  defp enrich_field(meta, enforce_keys, parent_module) do
    # Pattern-field metadata uses `:pattern` (a regex) instead of `:name`,
    # and is not subject to struct-key enforcement.
    base =
      case Map.get(meta, :name) do
        nil -> Map.put(meta, :enforce?, false)
        name -> Map.put(meta, :enforce?, name in enforce_keys)
      end

    case meta.kind do
      :sub_field ->
        (meta[:child_module] || Module.concat(parent_module, Codegen.atom_to_module(meta.name)))
        |> then(&Map.put(base, :sub_module, &1))

      _ ->
        base
    end
  end

  # For the top-level module, every section option is reachable via the
  # Spark-generated accessor — including ones the user didn't declare
  # (default applies, or `:error` for non-default options). For sub_field
  # submodules, only `authorized_fields` and `json` are tracked in the
  # local `__information__/0.options` map; everything else is `nil`.
  defp section_options(module, info) do
    if info.path == [] do
      %{
        enforce: opt(module, &guardedstruct_enforce/1),
        opaque: opt(module, &guardedstruct_opaque/1),
        module: opt(module, &guardedstruct_module/1),
        error: opt(module, &guardedstruct_error/1),
        authorized_fields: opt(module, &guardedstruct_authorized_fields/1),
        main_validator: opt(module, &guardedstruct_main_validator/1),
        validate_derive: opt(module, &guardedstruct_validate_derive/1),
        sanitize_derive: opt(module, &guardedstruct_sanitize_derive/1),
        json: opt(module, &guardedstruct_json/1)
      }
    else
      sub_opts = Map.get(info, :options, %{})

      %{
        enforce: nil,
        opaque: nil,
        module: nil,
        error: nil,
        authorized_fields: Map.get(sub_opts, :authorized_fields),
        main_validator: nil,
        validate_derive: nil,
        sanitize_derive: nil,
        json: Map.get(sub_opts, :json)
      }
    end
  end

  defp opt(module, fun) do
    case fun.(module) do
      {:ok, v} -> v
      _ -> nil
    end
  end
end
