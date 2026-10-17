# Cross-field core keys — `auto`, `from`, `on`, `domain`

Four options on `field` / `sub_field` / `conditional_field` that read other
parts of the input. Parsed once at compile time into `__from_path__`,
`__on_path__`, `__domain_ops__`.

## `auto`

Fill in a field from an MFA call.

```elixir
field :id, :string, auto: {Ecto.UUID, :generate}
field :slug, :string, auto: {MyApp.Slug, :from_title, [:title]}
```

| Form | Calls |
|---|---|
| `{Mod, :fun}` | `Mod.fun()` (no args) |
| `{Mod, :fun, arg}` | `Mod.fun(arg)` |

* In the default `:add` mode it runs whether or not the field was supplied, and
  **replaces** a value the caller sent. In `:edit` mode
  (`builder({:root, attrs, :edit})`) it runs only when the field is missing or
  `nil`, so a supplied value is kept.
* Compile-time verifier `VerifyAutoMFA` warns about an unknown MFA; the module
  still compiles.

## `from`

Copy a value from a path elsewhere in the input.

```elixir
field :user_id, :string, from: "headers::auth_user_id"
field :owner, :string, from: "root::username"
```

The string is split on `::` into a path. A leading `root` starts at the whole
input; any other path starts at the map the field sits in. The runtime reads
`get_in(input, [:headers, :auth_user_id])` and assigns it as the field's value.

* When the source holds a value, it **replaces** the field's own value, even one
  the caller sent.
* When the source is missing or `nil`, the field keeps its own value.

## `on`

A pre-condition: the field is **only allowed** when another path is present.
Useful for ownership ("`role_id` only present when `role` is sent").

```elixir
field :role_id, :string, on: "role"
field :owner_id, :string, on: "root::owner"
```

The path follows the same rules as `from`. It is present when `get_in/2` finds a
value that is not `nil`. The value itself is not compared. The gate only runs
when the field itself has a value; `enforce: true` makes the field required.

If the gate fails, the runtime emits a `:dependent_keys` error for the field.

To compare the value, use `domain`:

```elixir
field :role_id, :string, domain: "!role=String[admin]"
```

## `domain`

Cross-field constraint expressions. Compile-evaluated into a structured op map.

```elixir
field :status, :string, domain: "!auth_type=Atom[admin, moderator]"
```

Reads: "when `status` has a value, `auth_type` must be `:admin` or `:moderator`".
The `!` prefix also makes a missing `auth_type` an error; `?` lets it be
missing. The values of `Atom[...]` / `String[...]` are separated by commas
(`enum=` in a `derives:` string separates them with `::`). Works in
`GuardedStruct.AshResource` resources the same way as in standalone modules.

## Pipeline order

Per `do_pipeline/7` (`lib/guarded_struct/runtime.ex`):

1. `normalize_keys` — atom-convert keys (except `dynamic_field` values).
2. `authorized_fields` — reject unknown top-level keys when section opted in.
3. `check_enforce_keys` — required-fields check.
4. `apply_auto` — run the `auto` MFAs (`:add` replaces a supplied value, `:edit` keeps it).
5. `check_domain` — cross-field constraints.
6. `check_on` — conditional gates.
7. `apply_from` — copy from other paths.
8. Sub-field recursion.
9. Per-field validators.
10. `run_main_validator`.
11. Pass-1 derives over virtual fields.
12. Pass-2 derives over the merged map.
