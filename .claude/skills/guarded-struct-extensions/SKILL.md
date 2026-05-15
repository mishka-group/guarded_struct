---
name: guarded-struct-extensions
description: Use when defining or wiring custom validator/sanitizer ops via `use GuardedStruct.Derive.Extension`. Triggers on `derives do validator :name, fn -> ... end end` blocks, the `:derive_extensions` config key (Application or per-module), the `:config` sentinel, or any `__validate__/3` / `__sanitize__/2` callback.
---

# Custom derive extensions

Reference: `usage-rules/extensions.md`.

## Declaring an extension module

```elixir
defmodule MyApp.Derives do
  use GuardedStruct.Derive.Extension

  derives do
    validator :slug, fn input ->
      is_binary(input) and Regex.match?(~r/^[a-z0-9-]+$/, input)
    end

    sanitizer :slugify, fn input when is_binary(input) ->
      input |> String.downcase() |> String.replace(~r/[^a-z0-9-]+/u, "-")
    end
  end
end
```

The Spark transformer generates:

* `__validators__/0`, `__sanitizers__/0` — atom lists
* `__validate__(op, input, field)` — runtime dispatcher; `:__not_found__` on miss
* `__sanitize__(input, op)` — runtime dispatcher (pipe-friendly arg order)
* `__derive_extension__?/0` — marker

## Validator return contract

The `validator :name, fn input -> ... end` callback may return:

| Return | Meaning |
|---|---|
| `true` | Pass; value unchanged. |
| `false` | Fail with a default message. |
| `{:error, field, action, message}` | Explicit error. |
| Any other value | Used as the *coerced output*. |

## Sanitizer return contract

Whatever the function returns replaces the input. Sanitizers run before
validators.

## Registering

### Global

```elixir
# config/config.exs
config :guarded_struct, derive_extensions: [MyApp.Derives]
```

Cached in `:persistent_term` keyed by raw config. Auto-invalidates when the
config changes. Manual reset: `GuardedStruct.Derive.Extension.clear_cache/0`.

### Per-module

```elixir
use GuardedStruct, derive_extensions: [MyApp.Derives]            # this module only
use GuardedStruct, derive_extensions: [MyApp.Derives, :config]   # merge with global
```

The `:config` sentinel expands to the global list at the position it appears.
See `usage-rules/extensions.md` for full precedence rules.

## Shadow warning

Declaring `validator :string` or `sanitizer :trim` shadows a built-in op.
The Codegen transformer emits a `Spark.Warning.warn/3` pointing at the
entity's source line. `GuardedStruct.Derive.Registry.known_validate?/1` /
`known_sanitize?/1` decide what counts as built-in.

## Resolution in nested sub_field submodules

Auto-generated sub_field submodules **inherit** the root module's per-module
opt via the process-dict `:guarded_struct_current_module` flag. They never
declare their own `__guarded_derive_extensions_opt__/0` (`nil` from codegen).
Don't try to override per-submodule — set the opt on the root user module.
