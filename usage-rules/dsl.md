# GuardedStruct DSL — `field`, `sub_field`, `conditional_field`, `virtual_field`, `dynamic_field`

Every entity lives inside one `guardedstruct do … end` block.

## `field name, type, opts`

```elixir
field :email, :string,
  enforce: true,
  default: nil,
  derives: "sanitize(trim, downcase) validate(string, not_empty, email_r)",
  validator: {MyApp.Checks, :no_disposable_email},
  auto: {Ecto.UUID, :generate},
  from: "headers::auth_user_id",
  on: "profile::owner_id",
  hint: "primary-email"
```

| Option | Type | Purpose |
|---|---|---|
| `name` (positional) | atom | Field name. |
| `type` (positional) | quoted type | E.g. `:string`, `String.t()`, `:integer`. |
| `enforce` | boolean | Add to `@enforce_keys`. Missing input → `:required_fields` error. |
| `default` | quoted | Default if input omits the key. |
| `derives` | string | Op-string (see `guarded_struct:derive`). |
| `derive` | string | Legacy singular alias for `derives`. Honored for 0.0.x compat; prefer `derives`. |
| `validator` | `{Mod, :fn}` | Per-field validator MFA, called as `Mod.fn(name, value)`. |
| `auto` | `{Mod, :fn}` or `{Mod, :fn, arg}` | Auto-fill the field. |
| `from` | string | Pull value from another path. |
| `on` | string | Conditional rule referring to a path. |
| `domain` | string | Cross-field constraint expression. |
| `struct` | atom | Build value via `Mod.builder/1` (external GuardedStruct). |
| `structs` | atom or boolean | List-of items via `Mod.builder/1`, or `true` for list-of-self. |
| `hint` | string | Label propagated into the field's error maps. |
| `priority` | boolean | Conditional-field short-circuit marker. |

## `sub_field name, type, opts do … end`

Defines a nested submodule (e.g. `MyApp.User.Profile`) generated at compile time.
Same options as `field` plus:

* `error: true` — generates a per-level `Error` exception.
* `authorized_fields: true` — reject keys not declared in this sub_field.
* `main_validator: {Mod, :fn}` — runs after every nested field validates.

Children: nested `field`, `sub_field`, `conditional_field`.

## `conditional_field name, type, opts do … end`

Pick one child based on the input value. Children share the parent's `name`.
Each child is tried in order; the first whose `validator:` returns `{:ok, ...}`
wins. Use `priority: true` on at most one child to short-circuit.

* `structs: true` on the conditional — iterate a list, apply children
  per element.
* Aggregated error shape (on no match):

  ```elixir
  %{field: name, action: :conditionals, errors: [child_attempt_errors...]}
  ```

  Each inner `errors` entry follows the canonical error shape.

## `virtual_field name, type, opts`

Same surface as `field`, but the value is **dropped** from the final struct.
Useful for `password_confirmation`-style inputs consumed by `main_validator`
but not persisted. Schema accepts `name`, `type`, `enforce`, `default`,
`derives` (+ legacy `derive`), `validator`, `auto`, `from`, `on`, `domain`,
`hint`. Does **not** accept `struct`, `structs`, or `priority`.

## `dynamic_field name, opts`

Free-form map slot. The inner map is **identity-preserved** — keys are *not*
atomized at any depth. Used for attacker-controlled metadata where atom-table
growth would be a DoS risk. Schema accepts the same options as `virtual_field`
(no `struct` / `structs` / `priority`).

Defaults baked into the entity schema:

* `type` → `map()`
* `default` → `%{}`
* `derives` → `"validate(map)"`

The entity also auto-sets `__dynamic__: true` (internal flag — drives the
`:dynamic_field` kind in `__fields__/0` and tells `Parser.convert_to_atom_map`
to leave inner values untouched).

## `@derives "..."` / `@derive_rules "..."` decorators

Module attributes consumed by the **next** entity declaration. One-shot — the
attribute is cleared after the consuming entity, like `@doc`. Useful for
keeping fields short:

```elixir
@derives "sanitize(trim, downcase) validate(string, not_empty, email_r)"
field :email, :string, enforce: true

@derives "sanitize(trim) validate(string, max_len=24)"
field :nickname, :string
```

Available on `field`, `sub_field`, `conditional_field`, `virtual_field`,
`dynamic_field`.

## Section options — `guardedstruct opts do … end`

```elixir
guardedstruct enforce: true, authorized_fields: true, json: true do
  ...
end
```

| Option | Default | Purpose |
|---|---|---|
| `enforce` | `false` | Cascade `enforce: true` to every child without a default. |
| `opaque` | `false` | Generate `@opaque t()` instead of `@type t()`. |
| `module` | nil | Emit the struct into a sub-module name. |
| `error` | `false` | Generate a `Module.Error` exception. |
| `authorized_fields` | `false` | Reject unknown top-level keys with `:authorized_fields` error. |
| `main_validator` | nil | `{Mod, :fn}` runs after per-field validators. |
| `validate_derive` | nil | User-supplied validator module(s) for unknown ops. |
| `sanitize_derive` | nil | User-supplied sanitizer module(s) for unknown ops. |
| `json` | `false` | Auto-derive `Jason.Encoder` (or built-in `JSON.Encoder` ≥ 1.18). |
| `auto_wire` | `false` | Ash-only: inject `GuardedStruct.AshResource.Change` automatically. |

## Pattern-keyed maps

A `field` whose `name:` is a regex makes the module a *pattern map* — its
`builder/1` returns a plain map keyed by matching string keys, no defstruct.
Use for shard tables, dynamic configuration.

## What gets generated

Every guarded module gains at compile time:

* `defstruct`, `@enforce_keys`, `@type t()` / `@opaque t()`,
* `keys/0,1`, `enforce_keys/0,1`, `example/0`,
* `__information__/0`, `__fields__/0`, `__field_meta__/1`,
* `__guarded_information__/0`, `__guarded_fields__/0`, `__guarded_field_meta__/1`
  (Ash-compatible aliases),
* `builder/1,2`,
* compile-time flags: `__guarded_has_validator__/0`,
  `__guarded_has_main_validator__/0`, `__guarded_error_module__/0`,
  `__guarded_derive_extensions_opt__/0`,
* sub_field submodules with the same surface.
