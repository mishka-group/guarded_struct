# `guarded_struct` v0.1.0 — what's new

This document covers **only what changed or was added** in `0.1.0` compared
to the `0.0.x` macro-based line. Pre-existing features (`field`, `sub_field`,
`conditional_field`, the derive op registry, `builder/1`, `keys/0`,
`__information__/0`, the `Messages` i18n backend, `Helper.Extra`) are
unchanged in surface and are not re-documented here.

Each entry: **what it is** · **where it lives** · **real example**.

---

## 1 · Spark DSL rewrite (architecture)

The whole macro core was replaced with a `Spark.Dsl.Extension`. Public API
is unchanged — `use GuardedStruct`, `guardedstruct opts do … end`, `field`,
`sub_field`, `conditional_field`, `builder/1` all work identically.

**Concrete user-facing wins:**

- Editor autocomplete inside `guardedstruct do … end` (closes **#1**) via
  `Spark.ElixirSense.Plugin` — free, no setup.
- Compile-time errors now have file:line:column via `Spark.Error.DslError`
  (was: stack-traces pointing at macro internals).
- All derive strings, `from:`/`on:` paths, and `domain:` expressions are
  parsed **once at compile time**, not on every `builder/1` call.
- `enum=Map[…]` / `enum=Tuple[…]` / `equal=Map::…` operands pre-evaluated
  at compile time → zero `Code.eval_string/1` calls on the runtime hot path.

> Files: `lib/guarded_struct/dsl.ex`, all of `lib/guarded_struct/transformers/`,
> `lib/guarded_struct/verifiers/`.

---

## 2 · New section option — `jason: true`

> Schema: `lib/guarded_struct/dsl.ex` · injection: `lib/guarded_struct.ex:71`.
> Tests: `test/jason_encoder_test.exs`.

Opt-in auto-emission of `@derive Jason.Encoder` for the struct.

```elixir
defmodule Order do
  use GuardedStruct
  guardedstruct jason: true do
    field :id,    String.t(), enforce: true
    field :total, integer(),  enforce: true
  end
end

{:ok, o} = Order.builder(%{id: "abc", total: 99})
Jason.encode!(o)   # => ~s({"id":"abc","total":99})
```

---

## 3 · `derives:` is the canonical option name (soft deprecation of `derive:`)

> Resolver: `lib/guarded_struct/transformers/parse_derive.ex` (`resolve/2`).
> Tests: `test/derives_deprecation_test.exs`.

The plural form `derives:` is now canonical. `derive:` still works but
emits a `Spark.Warning.warn_deprecated/4` warning at compile time.

| Form | Status |
|---|---|
| `derives: "..."` | ✅ canonical |
| `derive: "..."` | ⚠️ soft-deprecated, removed in a future release |
| Both on one field | `derives:` wins, no warning |

```elixir
# new
field :email, String.t(), derives: "sanitize(trim) validate(email_r)"

# still works, but warns at compile time
field :email, String.t(), derive: "sanitize(trim) validate(email_r)"
```

---

## 4 · `@derive_rules` / `@derives` decorator

> AST walker: `lib/guarded_struct.ex` (`transform_derive_rules/1`).
> Tests: `test/derive_rules_decorator_test.exs`.

One-shot decorator that injects `derives:` into the **immediately-following**
`field` / `sub_field` / `conditional_field`. Cleaner than inline when the
rule is long. Consumed only by the next field, like `@doc`.

```elixir
guardedstruct do
  @derive_rules "validate(string, max_len=10)"
  field :name, String.t()

  @derives "validate(integer, min_len=0)"
  field :age, integer()

  field :plain, String.t()                 # not decorated
end
```

If both the decorator and an inline `derives:` are present, the inline
wins (decorator is silently skipped).

---

## 5 · New entity — `virtual_field` (closes #5)

> File: `lib/guarded_struct/dsl/virtual_field.ex`.
> Tests: `test/virtual_field_test.exs`.

Validated through the full pipeline but **excluded from `defstruct`**.
Useful for `password_confirm`-style values consumed only by `auto:` or
`main_validator/1`.

```elixir
guardedstruct do
  field :password,        String.t(), enforce: true
  field :hashed_password, String.t(),
    auto: {MyApp.Auth, :hash, :virtual_password}

  virtual_field :virtual_password, String.t(),
    derives: "validate(string, min_len=8)"
end
```

`:virtual_password` validates, feeds `auto:`, then disappears — never
in `%User{}`.

---

## 6 · New entity — `dynamic_field`

> Schema: `lib/guarded_struct/dsl.ex` (`@dynamic_field`).
> Tests: `test/virtual_field_test.exs` (the `WithDynamic` block).

Shorthand for a free-form map field. Defaults to `%{}`, type `map()`,
`derives: "validate(map)"` — all overridable.

```elixir
guardedstruct do
  field :id, String.t(), enforce: true
  dynamic_field :metadata     # equivalent to map() with default %{}
end

Doc.builder(%{id: "x", metadata: %{any: "shape", you: "want"}})
```

Keys at runtime are unrestricted (no atom-table-exhaustion DoS).

---

## 7 · Pattern-keyed map fields — regex `field` names (closes #11)

> Codegen: `lib/guarded_struct/transformers/codegen.ex` (Regex branch).
> Tests: `test/pattern_map_test.exs`.

A `field` whose first arg is a regex declares a pattern-keyed map. The
module's `builder/1` returns a **plain validated map** (no struct, since
Elixir struct keys are fixed at compile time).

```elixir
defmodule ShardsMap do
  use GuardedStruct
  guardedstruct do
    field ~r/^shard_\d+$/, struct(),
      struct: Shard,
      derives: "validate(map, not_empty)"
  end
end

ShardsMap.builder(%{
  "shard_1" => %{node: "10.0.0.1"},
  "shard_2" => %{node: "10.0.0.2"}
})
# => {:ok, %{"shard_1" => %Shard{...}, "shard_2" => %Shard{...}}}
```

- Returns a plain map, not a struct.
- Keys stay as strings (atom-table-exhaustion safe).
- Mixing atom-keyed and regex-keyed `field`s in one `guardedstruct`
  raises `Spark.Error.DslError` at compile time.

---

## 8 · Nested `conditional_field` (closes #7, #8, #25)

> Wiring: `recursive_as: :conditional_fields` in `lib/guarded_struct/dsl.ex`.
> Tests: `test/nested_conditional_field_test.exs`, `test/nested_sub_field_test.exs`.

The headline 0.0.x bug: `conditional_field` inside `conditional_field`
used to raise `unsupported_conditional_field` at parse time. Now it
works to arbitrary depth.

```elixir
guardedstruct do
  conditional_field :payment, any() do
    sub_field :payment, struct() do
      conditional_field :detail, any() do            # nested!
        field :detail, String.t(), hint: "string variant"
        sub_field :detail, struct(), hint: "map variant" do
          field :id, String.t()
        end
      end
    end
  end
end
```

`__information__/0`'s `conditional_keys` is now populated correctly
(was always `[]` in 0.0.x — fixed in 0.1.0).

---

## 9 · New validator op — `record=Tag` (closes #6)

> File: `lib/guarded_struct/derive/validation_derive.ex`.
> Tests: `test/record_test.exs`.

Validates Erlang Records / Elixir `Record.defrecord/2` tagged tuples.

```elixir
require Record
Record.defrecord(:user, name: nil, age: nil)

defmodule Wrapper do
  use GuardedStruct
  guardedstruct do
    field :u, :tuple, derives: "validate(record=user)"
  end
end

Wrapper.builder(%{u: user(name: "Alice", age: 30)})
# => {:ok, %Wrapper{u: {:user, "Alice", 30}}}
```

---

## 10 · `GuardedStruct.Validate` — schema without `builder/1` (closes #2)

> File: `lib/guarded_struct/validate.ex`.
> Tests: `test/validate_test.exs`.

Three-tier API for using a schema without going through the full builder.

| Function | One-line description |
|---|---|
| `Validate.run/2` | Apply a derive op-string to one value, no module needed |
| `Validate.field/4` | Validate one named field of a `guardedstruct` module; modes `:strict` / `:isolated`; pass `context:` for cross-field deps |
| `Validate.partial/2` | Validate a subset of fields — missing fields skipped (no enforce_keys check) |

```elixir
GuardedStruct.Validate.run("validate(string, email_r)", "x@y.io")
# => {:ok, "x@y.io"}

GuardedStruct.Validate.field(User, :email, "x@y.io")
# => {:ok, "x@y.io"}

GuardedStruct.Validate.field(User, :child_email, "p@x.io",
  context: %{account_type: "personal"})
# resolves cross-field on:/domain: deps from context

GuardedStruct.Validate.field(User, :child_email, "p@x.io", mode: :isolated)
# skips cross-field deps entirely

GuardedStruct.Validate.partial(User, %{email: "x@y.io"})
# => {:ok, %{email: "x@y.io"}} — missing `:name` doesn't error
```

---

## 11 · `GuardedStruct.Diff` — field-level diff/patch

> File: `lib/guarded_struct/diff.ex`.
> Tests: `test/diff_test.exs`.

| Function | One-line description |
|---|---|
| `Diff.diff/2` | Field-by-field change map, recurses into sub_field structs |
| `Diff.apply/2` | Apply a diff back onto a struct |
| `Diff.equal?/2` | Field-by-field equality (short-circuits) |

```elixir
a = %User{name: "Alice", age: 30}
b = %User{name: "Alice", age: 31}

GuardedStruct.Diff.diff(a, b)
# => %{age: {:changed, 30, 31}}

GuardedStruct.Diff.apply(a, %{age: {:changed, 30, 31}})
# => %User{name: "Alice", age: 31}
```

---

## 12 · `GuardedStruct.Errors` — Splode error wrapper

> Files:
> - `lib/guarded_struct/errors.ex` — `Splode` root class
> - `lib/guarded_struct/errors/invalid.ex`
> - `lib/guarded_struct/errors/validation.ex`
> - `lib/guarded_struct/errors/unknown.ex`
>
> Tests: `test/errors_test.exs`.

Opt-in conversion of `builder/1`'s `{:error, [...]}` list into typed
Splode exceptions with `traverse_errors`, `set_path`, JSON-encodable
shape.

```elixir
case User.builder(input) do
  {:error, errs} ->
    class = GuardedStruct.Errors.from_tuple(errs)
    GuardedStruct.Errors.traverse_errors(class, &Exception.message/1)
  ok -> ok
end
```

---

## 13 · `GuardedStruct.Schema` — JSON Schema / OpenAPI / TypeScript (closes #3)

> File: `lib/guarded_struct/schema.ex`.
> Tests: `test/schema_test.exs`.

| Function | Output |
|---|---|
| `Schema.json_schema/1` | JSON Schema 2020-12 map |
| `Schema.openapi/1` | OpenAPI 3.1 `components.schemas` envelope |
| `Schema.typescript/1` | TypeScript `interface` source |

```elixir
GuardedStruct.Schema.json_schema(User)
# => %{"$schema" => "...", "type" => "object", "properties" => ..., "required" => [...]}

GuardedStruct.Schema.openapi([User, Order])
# => %{"openapi" => "3.1.0", "components" => %{"schemas" => %{"User" => ..., "Order" => ...}}}

GuardedStruct.Schema.typescript(User)
# => "export interface User {\n  name: string;\n  age?: number;\n}\n"
```

---

## 14 · `GuardedStruct.AshResource` — Ash extension

> Files:
> - `lib/guarded_struct/ash_resource.ex`
> - `lib/guarded_struct/ash_resource/info.ex`
> - `lib/guarded_struct/transformers/generate_ash_validator.ex`
>
> Tests: `test/ash_resource_test.exs`.

Bolts the `guardedstruct do … end` block onto an Ash resource without
redefining its `defstruct`. Exposes three hooks:

| Function | One-line description |
|---|---|
| `__guarded_validate__/1` | Run the validate pipeline on input attrs |
| `__guarded_information__/0` | Same metadata as standalone, separate namespace |
| `__guarded_fields__/0` | Internal field-meta list (Ash namespace) |

```elixir
defmodule MyApp.User do
  use Ash.Resource, domain: MyApp.Domain,
    extensions: [GuardedStruct.AshResource]

  attributes do
    uuid_primary_key :id
    attribute :email, :string, allow_nil?: false
  end

  guardedstruct do
    field :email, :string,
      derives: "sanitize(trim, downcase) validate(string, email_r)"
  end
end

MyApp.User.__guarded_validate__(%{email: "  ALICE@X.IO  "})
# => {:ok, %{email: "alice@x.io"}}
```

---

## 15 · `GuardedStruct.Derive.Extension` — custom validators / sanitizers

> File: `lib/guarded_struct/derive/extension.ex`.
> Tests: `test/derive_extension_test.exs`.

Spark-native DSL for declaring custom `validate(my_op)` / `sanitize(my_op)`
ops. Replaces the legacy `Application.put_env(:guarded_struct, :validate_derive, …)`
plugin path (which still works for back-compat).

```elixir
defmodule MyApp.Derives do
  use GuardedStruct.Derive.Extension

  validator :slug, fn s ->
    is_binary(s) and Regex.match?(~r/^[a-z0-9-]+$/, s)
  end

  sanitizer :slugify, fn s when is_binary(s) ->
    s |> String.downcase() |> String.replace(~r/[^a-z0-9-]+/u, "-")
  end
end

# config/config.exs
config :guarded_struct, derive_extensions: [MyApp.Derives]

# any module:
field :slug, String.t(), derives: "sanitize(slugify) validate(slug)"
```

---

## 16 · `GuardedStruct.Info` — Spark info accessors

> File: `lib/guarded_struct/info.ex`.

Typed accessors over compiled DSL state.

| Function | One-line description |
|---|---|
| `Info.fields/1` | Spark-derived list of all field entities |
| `Info.enforce_keys/1` | Required field names for a module |
| `Info.field/2` | Look up one field's meta by name |
| `Info.field?/2` | `true`/`false` — does this field exist? |

```elixir
GuardedStruct.Info.field?(User, :email)            # => true
GuardedStruct.Info.field(User, :email).derives     # => "validate(email_r)"
```

---

## 17 · Telemetry events on `builder/1`

> Emission: `lib/guarded_struct/runtime.ex` (`with_telemetry/2`).
> Tests: `test/telemetry_test.exs`.

| Event | Measurements | Metadata |
|---|---|---|
| `[:guarded_struct, :builder, :start]` | `system_time` | `module` |
| `[:guarded_struct, :builder, :stop]` | `duration` | `module, result, error_count` |
| `[:guarded_struct, :builder, :exception]` | `duration` | `module, kind, reason, stacktrace` |

Only top-level `builder/1` emits — nested sub_field builds don't, so
you don't drown in events.

```elixir
:telemetry.attach(
  "log-builds",
  [:guarded_struct, :builder, :stop],
  &MyApp.Logger.on_build/4,
  nil
)
```

---

## 18 · Generated `example/0` REPL helper

> Emission: `lib/guarded_struct/transformers/codegen.ex` (`example_value_ast/2`).
> Tests: `test/example_helper_test.exs`.

Every `guardedstruct` module gets a free `example/0` that returns a
struct using `default:` values + type-based fallbacks (`String.t() → ""`,
`integer() → 0`, etc.). Recurses for `sub_field`s. Pattern-keyed map
modules emit `def example, do: %{}`.

```elixir
defmodule User do
  use GuardedStruct
  guardedstruct do
    field :name, String.t(), default: "Anon"
    field :age,  integer(),  default: 0
    field :email, String.t()
    sub_field :auth, struct() do
      field :role, String.t(), default: "user"
    end
  end
end

User.example()
# => %User{name: "Anon", age: 0, email: "", auth: %User.Auth{role: "user"}}
```

Useful in iex/livebook and as a fixture in tests.

---

## 19 · Compile-time strict modes (opt-in)

> Config: read by transformers at compile time.

### `:strict_derive_ops` — typo suggestion + unknown-op rejection

> File: `lib/guarded_struct/transformers/verify_derive_ops.ex`.
> Tests: `test/verify_derive_ops_test.exs`.

Unknown derive ops fail with `Spark.Error.DslError` + a "did you mean…"
suggestion via `String.jaro_distance/2` (threshold 0.7, top-3).
Automatically skipped if a `derive_extensions:` plugin is registered.

```elixir
# config/config.exs
config :guarded_struct, strict_derive_ops: true

field :age, integer(), derives: "validate(intger)"   # typo
# ** (Spark.Error.DslError) unknown derive op(s) on field :age: validate=:intger
#    Did you mean `:integer`?
```

### `:strict_core_key_paths` — `from:` / `on:` path verification

> File: `lib/guarded_struct/transformers/verify_core_key_paths.ex`.
> Tests: `test/verify_core_key_paths_test.exs`.

```elixir
config :guarded_struct, strict_core_key_paths: true

field :dest, String.t(), from: "root::nope"
# ** (Spark.Error.DslError) `from: "nope"` on field :dest references
#    `:nope`, which is not a declared field.
```

---

## 20 · Compile-time param-type validation

> File: `lib/guarded_struct/derive/op_param_validator.ex`.
> Tests: `test/op_param_validator_test.exs`.

Catches malformed parameterised derive ops at compile time, not at the
first failing call.

```elixir
field :name, String.t(), derives: "validate(max_len=foo)"
# ** (Spark.Error.DslError) `:max_len` expects a non-negative integer,
#    got "foo" on field :name.
```

Catches: `max_len`, `min_len`, `regex`, `enum`, `equal`, `record`, `tag`,
`custom` shape errors.

---

## 21 · Cycle detection for `struct:` / `structs:`

> File: `lib/guarded_struct/verifiers/verify_no_struct_cycles.ex`.
> Tests: `test/verify_no_struct_cycles_test.exs`.

Post-compile verifier that walks transitive `struct:` / `structs:`
references and rejects self-cycles or A→B→A loops.

```elixir
defmodule A do
  use GuardedStruct
  guardedstruct do
    field :b, struct(), struct: B
  end
end
defmodule B do
  use GuardedStruct
  guardedstruct do
    field :a, struct(), struct: A   # cycle
  end
end
# ** (Spark.Error.DslError) struct cycle detected: A → B → A
```

---

## 22 · Mix tasks (Igniter-based)

> Under `lib/mix/tasks/`. All gracefully degrade if `:igniter` isn't loaded.

| Task | One-line description |
|---|---|
| `mix guarded_struct.install` | Add dep, register `lint` alias, seed `derive_extensions: []`; flags `--strict`, `--strict-paths` |
| `mix guarded_struct.gen.struct` | Scaffold a starter module from CLI; `name!:type` syntax for enforce |
| `mix guarded_struct.gen.schema` | Emit JSON Schema / TypeScript / OpenAPI for a module |

```sh
mix igniter.install guarded_struct --strict --strict-paths

mix guarded_struct.gen.struct MyApp.User name!:string age:integer email:email
# => emits lib/my_app/user.ex with fields + sensible `derives:` defaults

mix guarded_struct.gen.schema MyApp.User --format=openapi --out=priv/api.json
```

---

## 23 · Application env / configuration keys

| Key | One-line description |
|---|---|
| `derive_extensions: [Mod, ...]` | Custom-op modules registered via `Derive.Extension` |
| `strict_derive_ops: true` | Reject unknown derive ops at compile time |
| `strict_core_key_paths: true` | Reject unresolved `from:` / `on:` paths at compile time |
| `message_backend: Mod` | i18n backend module (existed in 0.0.4, full coverage restored) |

```elixir
# config/config.exs
config :guarded_struct,
  derive_extensions: [MyApp.Derives],
  strict_derive_ops: true,
  strict_core_key_paths: true,
  message_backend: MyApp.GuardedStructMessages
```

---

## 24 · Parser hardening (bug fix)

> File: `lib/guarded_struct/derive/parser.ex`.
> Caught by `test/parser_property_test.exs`.

Property-based test caught a real crash — invalid UTF-8 inputs raised
`UnicodeConversionError`. Fixed by:
- `:binary.bin_to_list/1` instead of `String.to_charlist/1`
- Top-level `rescue _ -> nil` honouring the lenient parser contract
- `Code.string_to_quoted/2` called with `emit_warnings: false` for fuzz inputs

---

## 25 · Protocol consolidation tweak

> File: `mix.exs` — `consolidate_protocols: Mix.env() != :test`.

Lets test fixtures register `Jason.Encoder` implementations after the
protocol set is normally frozen, so `jason: true` actually works in tests.

---

## 26 · Dependencies added

> File: `mix.exs`.

| Dep | Scope | Why |
|---|---|---|
| `{:spark, "~> 2.7"}` | runtime | DSL extension framework |
| `{:splode, "~> 0.3"}` | runtime | Error class hierarchy |
| `{:telemetry, "~> 1.0"}` | runtime | Builder events |
| `{:igniter, "~> 0.7"}` | dev/test | Installer + scaffolder mix tasks |
| `{:sourceror, "~> 1.7"}` | dev/test | Source-mapping for installer |
| `{:stream_data, "~> 1.0"}` | test | Property-based parser tests |
| `{:jason, "~> 1.0"}` | test | `jason: true` opt-in test coverage |

Optional deps unchanged: `html_sanitize_ex`, `email_checker`, `ex_url`,
`ex_phone_number`, `sweet_xml`.

---

## 27 · Tooling integration

| Tool | One-line description |
|---|---|
| `mix lint` alias | Chains `mix spark.formatter` then `mix format` (seeded by installer) |
| `mix spark.formatter` | Works without `--extensions` flag — wired via mix alias |
| `mix spark.cheat_sheets` | Auto-generates `documentation/dsls/*.md` cheat sheets |
| `documentation/dsls/DSL-GuardedStruct.md` | Generated DSL cheat sheet |
| `documentation/dsls/DSL-GuardedStruct.AshResource.md` | Generated Ash-extension cheat sheet |
| `guidance/guarded-struct.livemd` | LiveBook tour with "What's new in 0.1.0" section |
| ElixirSense / Lexical autocomplete | Free via `Spark.ElixirSense.Plugin` (closes **#1**) |

---

## 28 · Bug fixes worth flagging

- `__information__/0`'s `conditional_keys` is now populated correctly
  (was always `[]` in 0.0.x).
- All 14 orchestration-layer `Messages` callbacks (`required_fields`,
  `authorized_fields`, `builder`, `check_dependent_keys`, etc.) are
  reachable again — some were dead code in 0.0.x.
- `MyStruct.Error.message/1` format matches master and uses
  `translated_message(:message_exception)` for i18n.
- Parser no longer crashes on invalid UTF-8 (see §24).
- Pre-evaluated `enum=Map[…]` / `equal=Map::…` — zero runtime
  `Code.eval_string/1` calls in the hot path.

---

# Index — new files in `0.1.0`

```
lib/guarded_struct/dsl.ex                                  · Spark extension definition
lib/guarded_struct/dsl/virtual_field.ex                    · NEW virtual_field target
lib/guarded_struct/validate.ex                             · NEW standalone Validate.run/field/partial
lib/guarded_struct/diff.ex                                 · NEW Diff helpers
lib/guarded_struct/errors.ex                               · NEW Splode root class
lib/guarded_struct/errors/{invalid,validation,unknown}.ex  · NEW Splode subclasses
lib/guarded_struct/schema.ex                               · NEW json_schema / openapi / typescript
lib/guarded_struct/ash_resource.ex                         · NEW Ash extension
lib/guarded_struct/ash_resource/info.ex                    · NEW Ash-namespaced info
lib/guarded_struct/info.ex                                 · NEW Spark.InfoGenerator wrapper
lib/guarded_struct/runtime.ex                              · build/3 + NEW telemetry wrapper
lib/guarded_struct/derive/op_evaluator.ex                  · NEW compile-time pre-evaluator
lib/guarded_struct/derive/op_param_validator.ex            · NEW compile-time param-type check
lib/guarded_struct/derive/extension.ex                     · NEW custom-op DSL (Spark-native)
lib/guarded_struct/transformers/parse_derive.ex            · NEW canonicaliser + deprecation
lib/guarded_struct/transformers/verify_derive_ops.ex       · NEW strict mode + typo suggestion
lib/guarded_struct/transformers/parse_core_keys.ex         · NEW
lib/guarded_struct/transformers/verify_core_key_paths.ex   · NEW strict path check
lib/guarded_struct/transformers/parse_domain.ex            · NEW
lib/guarded_struct/transformers/generate_sub_field_modules.ex · NEW
lib/guarded_struct/transformers/generate_builder.ex        · NEW
lib/guarded_struct/transformers/codegen.ex                 · NEW (incl. example/0 + regex-named field)
lib/guarded_struct/transformers/generate_ash_validator.ex  · NEW
lib/guarded_struct/verifiers/verify_validator_mfa.ex       · NEW post-compile MFA check
lib/guarded_struct/verifiers/verify_auto_mfa.ex            · NEW post-compile MFA check
lib/guarded_struct/verifiers/verify_no_struct_cycles.ex    · NEW cycle detection
lib/mix/tasks/guarded_struct.install.ex                    · NEW Igniter installer
lib/mix/tasks/guarded_struct.gen.struct.ex                 · NEW Igniter scaffolder
lib/mix/tasks/guarded_struct.gen.schema.ex                 · NEW json/typescript/openapi emitter
```

(Pre-existing files like `lib/messages.ex`, `lib/guarded_struct/helper/extra.ex`,
`lib/guarded_struct/derive/{registry,parser,sanitizer_derive,validation_derive}.ex`
were either preserved verbatim or rewritten internally without changing
their public surface, so they're not relisted here.)
