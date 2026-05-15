# Custom derive extensions — `use GuardedStruct.Derive.Extension`

Add project-specific `sanitize(<op>)` / `validate(<op>)` atoms via a Spark DSL.

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

The extension module exposes:

* `__validators__/0`, `__sanitizers__/0` — atom lists for compile-time checks.
* `__validate__(op, input, field)` — runtime dispatcher; returns `:__not_found__` when the op isn't declared.
* `__sanitize__(input, op)` — runtime dispatcher (pipe-friendly arg order).
* `__derive_extension__?/0` — `true`, so the registry filter accepts it.

## Registering an extension

### Global (Application config)

```elixir
# config/config.exs
config :guarded_struct, derive_extensions: [MyApp.Derives]
```

Resolved at boot, cached in `:persistent_term`. Invalidates automatically when
the config changes; call `GuardedStruct.Derive.Extension.clear_cache/0` from
test setup if you mutate the env at runtime.

### Per-module

```elixir
use GuardedStruct, derive_extensions: [MyApp.Derives]
# or compose with global config:
use GuardedStruct, derive_extensions: [MyApp.Derives, :config]
```

Resolution rules:

| Opt | Result |
|---|---|
| `nil` | Global only. |
| `[]` | No extensions (opt-out). |
| `[A, B]` | `[A, B]` only — global ignored. |
| `[:config, A]` | global ++ `[A]` (global wins on op-name collisions). |
| `[A, :config]` | `[A]` ++ global (A wins). |
| `[A, :config, B]` | `[A]` ++ global ++ `[B]`. |

## Validator return contract

The function passed to `validator/2` may return:

* `true` — input passes, value unchanged.
* `false` — input fails with a generic message.
* `{:error, field, action, message}` — explicit error.
* Any other value — used as the *coerced output* (replaces the input).

## Sanitizer return contract

Return value replaces the input. Sanitizers run before validators.

## Compile-time shadow warning

Declaring `validator :string` / `sanitizer :trim` shadows a built-in.
The Codegen transformer emits a `Spark.Warning.warn/3` pointing at the
offending entity's source line; the registry's `known_validate?/1` /
`known_sanitize?/1` decide what counts as built-in.
