# GuardedStruct

Spark-based DSL for declaring validated, sanitized, immutable structs with rich
introspection. Optional Ash 3.x integration through the
`GuardedStruct.AshResource` extension.

```elixir
defmodule MyApp.User do
  use GuardedStruct

  guardedstruct do
    field :email, :string,
      enforce: true,
      derives: "sanitize(trim, downcase) validate(string, not_empty, email_r)"

    field :nickname, :string, derives: "sanitize(trim) validate(string, max_len=24)"

    sub_field :profile, :map do
      field :bio, :string, derives: "validate(string, max_len=200)"
    end
  end
end

MyApp.User.builder(%{email: "  Alice@X.IO  "})
# => {:ok, %MyApp.User{email: "alice@x.io", ...}}
```

## Map

| Topic | Sub-rule |
|---|---|
| `field` / `sub_field` / `conditional_field` / `virtual_field` / `dynamic_field` and section options | `guarded_struct:dsl` |
| `derives:` string mini-language; built-in sanitize/validate ops | `guarded_struct:derive` |
| `conditional_field` runtime dispatch and error aggregation | `guarded_struct:conditional` |
| Per-field `validator:` and section-level `main_validator:` | `guarded_struct:validators` |
| Cross-field `auto:`, `from:`, `on:`, `domain:` | `guarded_struct:core-keys` |
| Custom ops via `use GuardedStruct.Derive.Extension` | `guarded_struct:extensions` |
| `GuardedStruct.AshResource` — same DSL inside `use Ash.Resource` | `guarded_struct:ash` |
| `Builder`, `Validate`, `Diff`, `Info` runtime API | `guarded_struct:api` |
| Error shape, Splode wrapping, telemetry | `guarded_struct:errors` |

## Universal contracts

* `Module.builder/1,2` returns `{:ok, %Module{}}` or `{:error, [error_map]}`.
  The error tuple's second element is **always a list** (never a single map).
* Every error map has the canonical shape:
  `%{field: atom(), action: atom(), message: String.t(), [errors: [error_map]]}`.
  Multi-field errors (`:required_fields`, `:authorized_fields`) emit one entry per field.
* Sanitizer / validator pipelines use pipe-friendly order: `value |> sanitize(:op)`.
* All section + field metadata is parsed at compile time. `__information__/0`,
  `__fields__/0`, `__field_meta__/1`, `__guarded_field_name_set__/0` (Ash) are
  baked into the generated module — no runtime introspection on the hot path.

## Compile-time guarantees

The Spark layer runs verifiers that reject the module at compile time when:

* a `validator: {Mod, :fn}` MFA doesn't export the function (`VerifyValidatorMFA`),
* an `auto: {Mod, :fn}` MFA doesn't exist (`VerifyAutoMFA`),
* a `struct:` or `structs:` target creates a cycle (`VerifyNoStructCycles`).

Malformed `derives:` strings fail compilation with `Spark.Error.DslError` pointing
at the offending field's source line.
