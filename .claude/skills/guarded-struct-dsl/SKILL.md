---
name: guarded-struct-dsl
description: Use when writing or modifying a `guardedstruct do ... end` block. Triggers on `field`, `sub_field`, `conditional_field`, `virtual_field`, `dynamic_field` declarations, section options like `enforce:`, `authorized_fields:`, `error:`, `json:`, `main_validator:`, or when the generated module surface (`__information__/0`, `__fields__/0`, `__field_meta__/1`, `keys/0,1`, `enforce_keys/0,1`, `example/0`) is being read or queried.
---

# GuardedStruct DSL

Reference: `usage-rules/dsl.md` in the project root.

## Quick template

```elixir
defmodule MyApp.User do
  use GuardedStruct

  guardedstruct enforce: true, json: true do
    field :id, :string, auto: {Ecto.UUID, :generate}
    field :email, :string,
      derives: "sanitize(trim, downcase) validate(string, not_empty, email_r)"

    sub_field :profile, :map do
      field :bio, :string, derives: "validate(string, max_len=200)"
      field :country, :string, derives: "validate(string, min_len=2, max_len=2)"
    end

    conditional_field :owner, any() do
      field :owner, struct(), struct: MyApp.Person, validator: {Checks, :is_map_data}
      field :owner, String.t(), validator: {Checks, :is_string_data},
            derives: "validate(url)"
    end

    virtual_field :password_confirmation, :string
    dynamic_field :metadata
  end
end
```

## Entity reference

| Entity | Generates | Notes |
|---|---|---|
| `field` | struct slot | `:dynamic_field` kind when `dynamic_field` macro used. |
| `sub_field` | nested submodule (`MyApp.User.Profile` etc.) | Recursive; own `error:`/`authorized_fields:`/`main_validator:`. |
| `conditional_field` | one runtime-selected child | Children share parent's name. ≤ 1 `priority: true` child. |
| `virtual_field` | input-only, dropped from struct | Validated by main_validator; ideal for `password_confirmation`. No `struct`/`structs`/`priority`. |
| `dynamic_field` | passthrough map, no key-atomization | Default `validate(map)`. Atom-attack safe. No `struct`/`structs`/`priority`. |

## Section options

```elixir
guardedstruct enforce: true,        # cascade to every child without default
              opaque: true,         # @opaque t() instead of @type t()
              module: MyOther,      # emit struct into nested module
              error: true,          # generate MyApp.User.Error exception
              authorized_fields: true,  # reject unknown top-level keys
              main_validator: {Checks, :consistency},
              json: true,           # auto-derive Jason/JSON encoder
              auto_wire: true       # (Ash only) inject Change automatically
```

## Generated functions on every guarded module

- `defstruct`, `@enforce_keys`, `@type t()` / `@opaque t()`
- `keys/0,1`, `enforce_keys/0,1` — `:all` arg recurses sub_fields
- `example/0` — populated from defaults + type-based placeholders
- `__information__/0` — full DSL metadata; includes `:keys`,
  `:enforce_keys`, `:conditional_keys`, `:virtual_keys`, `:dynamic_keys`,
  `:options`
- `__fields__/0` — full per-field metadata list
- `__field_meta__/1` — O(1) lookup by name
- `__guarded_information__/0`, `__guarded_fields__/0`, `__guarded_field_meta__/1`
  — Ash-compatible aliases (always defined, even in standalone)
- `__guarded_has_validator__/0`, `__guarded_has_main_validator__/0`,
  `__guarded_error_module__/0`, `__guarded_derive_extensions_opt__/0`
  — compile-time-baked predicates / pointers
- `builder/1,2` — public entry point

## `@derives` decorator (alternative to inline `derives:`)

A module attribute consumed by the **next** entity. One-shot, cleared after.

```elixir
@derives "sanitize(trim, downcase) validate(email_r)"
field :email, :string, enforce: true
```

Also accepted: `@derive_rules`. Same semantics.

## Don'ts

* Don't call `function_exported?` on a guarded module to check for these
  generated functions — they're guaranteed at compile time.
* Don't mix atom-keyed and regex-keyed `field` declarations in the same
  `guardedstruct` block — `classify_shape/1` rejects this at compile time.
* Don't pass `:fields` (plural) to `enforce` — section-level `enforce: true`
  cascades automatically.
