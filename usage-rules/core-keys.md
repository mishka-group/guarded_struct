# Cross-field core keys — `auto`, `from`, `on`, `domain`

Four options on `field` / `sub_field` / `conditional_field` that read other
parts of the input. Parsed once at compile time into `__from_path__`,
`__on_path__`, `__domain_ops__`.

## `auto`

Fill in a missing field from an MFA call.

```elixir
field :id, :string, auto: {Ecto.UUID, :generate}
field :slug, :string, auto: {MyApp.Slug, :from_title, [:title]}
```

| Form | Calls |
|---|---|
| `{Mod, :fun}` | `Mod.fun()` (no args) |
| `{Mod, :fun, arg}` | `Mod.fun(arg)` |

* Runs only when the field is **missing** from input. To overwrite supplied
  values, look at the type marker `:edit` vs `:add` on `do_pipeline`.
* Compile-time verifier `VerifyAutoMFA` rejects unknown MFAs.

## `from`

Pull a value from a path elsewhere in the input.

```elixir
field :user_id, :string, from: "headers::auth_user_id"
```

The string is split on `::` into a path. The runtime reads
`get_in(input, [:headers, :auth_user_id])` and assigns it as the field's value
*if the field is unset*.

## `on`

A pre-condition: the field is **only allowed** when another path satisfies a
predicate. Useful for conditional ownership ("`role_id` only present when
`role: :admin`").

```elixir
field :role_id, :string, on: "role"        # role_id requires role to be set
field :role_id, :string, on: "role=admin"  # role_id requires role == "admin"
```

If the gate fails, the runtime emits a `:domain_parameters` / `:on` error.

## `domain`

Cross-field constraint expressions. Compile-evaluated into a structured op map.

```elixir
field :status, :string, domain: "!auth_type=Atom[admin::moderator]"
```

Reads: "this field is **required** when `auth_type` is in `[:admin, :moderator]`".
Supports `:enum`, `:equal`, presence (`!`), and absence checks.

## Pipeline order

Per `do_pipeline/7` (`lib/guarded_struct/runtime.ex`):

1. `normalize_keys` — atom-convert keys (except `dynamic_field` values).
2. `authorized_fields` — reject unknown top-level keys when section opted in.
3. `check_enforce_keys` — required-fields check.
4. `apply_auto` — fill missing fields via MFAs.
5. `check_domain` — cross-field constraints.
6. `check_on` — conditional gates.
7. `apply_from` — pull from other paths.
8. Sub-field recursion.
9. Per-field validators.
10. `run_main_validator`.
11. Pass-1 derives over virtual fields.
12. Pass-2 derives over the merged map.
