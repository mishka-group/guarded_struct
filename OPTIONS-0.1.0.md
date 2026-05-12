# `guarded_struct` v0.1.0 — what's new (focused review)

This is the **post-review** version of the options doc. The earlier, more
exhaustive version covered every new feature; we've since locked the
fixture-tested features in via dedicated tests under `test/support/fixtures/`
+ `test/fixtures/`. What remains here is the surface that hasn't been
fixture-tested — primarily **generators** (schema emission, scaffolders,
installer), config-level switches, tooling, and dep changes.

For everything else (DSL features, runtime behaviors, the `derives:` engine,
custom extensions, etc.) see the per-fixture test files — each is a
self-contained, asserted spec of one feature area:

```
test/support/fixtures/
├── forms.ex                       → virtual_field + validator transform + main_validator + jason
├── cross_field.ex                 → from / on / auto / domain + enforce-cascade
├── decorated.ex                   → @derives decorator
├── decorated_all_entities.ex      → @derives on every entity type at every depth
├── inline_all_entities.ex         → inline derives: on every entity type at every depth
├── mixed_decorator_inline.ex      → mixing both forms
├── conditionals.ex                → nested conditional_field (Block + 7-level Document)
├── dynamic.ex                     → dynamic_field + pattern-keyed map
├── records.ex                     → Erlang Record support
├── custom_derives.ex              → Derive.Extension (custom ops)
└── showcase.ex                    → integration showcase (jason, Diff, Validate, Errors, Info)
```

What lives in this doc:

1. JSON Schema / OpenAPI / TypeScript generator
2. Mix tasks (installer + scaffolder + schema emitter)
3. Compile-time strict modes (config-level switches)
4. Application env / configuration keys
5. Protocol consolidation tweak
6. Tooling integration (`mix lint`, cheat sheets, LiveBook, autocomplete)
7. Dependencies added
8. Bug-fix highlights worth flagging on the release notes

---

## 1 · Schema generators — `GuardedStruct.Schema`

> Files:
> - `lib/guarded_struct/schema.ex`
> - `lib/mix/tasks/guarded_struct.gen.schema.ex` (Igniter mix task wrapper)
>
> Tests: `test/schema_test.exs`.
> Closes issue **#3**.

Emit a JSON Schema / OpenAPI envelope / TypeScript declaration from any
`GuardedStruct` module. Useful for:

- API spec generation (front-end TypeScript types, OpenAPI docs)
- JSON Schema validation outside the Elixir runtime
- Auto-doc generation for partner integrations

| Function | Output |
|---|---|
| `Schema.json_schema/1` | JSON Schema 2020-12 map |
| `Schema.openapi/1` | OpenAPI 3.1 `components.schemas` envelope |
| `Schema.typescript/1` | TypeScript `interface` declaration |

```elixir
defmodule MyApp.User do
  use GuardedStruct
  guardedstruct do
    field :name,  String.t(), enforce: true, derives: "validate(string, max_len=80)"
    field :email, String.t(), enforce: true, derives: "validate(email_r)"
    field :age,   integer(),                  derives: "validate(integer)"
  end
end

GuardedStruct.Schema.json_schema(MyApp.User)
# => %{
#      "$schema" => "https://json-schema.org/draft/2020-12/schema",
#      "title"   => "MyApp.User",
#      "type"    => "object",
#      "properties" => %{
#        "name"  => %{"type" => "string", "maxLength" => 80},
#        "email" => %{"type" => "string", "format" => "email"},
#        "age"   => %{"type" => "integer"}
#      },
#      "required" => ["name", "email"]
#    }

GuardedStruct.Schema.openapi([MyApp.User, MyApp.Order])
# => %{
#      "openapi" => "3.1.0",
#      "info"    => %{"title" => "GuardedStruct schemas", "version" => "1.0.0"},
#      "components" => %{
#        "schemas" => %{
#          "MyApp_User"  => %{...},
#          "MyApp_Order" => %{...}
#        }
#      }
#    }

GuardedStruct.Schema.typescript(MyApp.User)
# => "export interface MyAppUser {\n  name: string;\n  email: string;\n  age?: number;\n}\n"
```

Mapping rules (op → schema constraint):

| Derive op | JSON Schema | TypeScript |
|---|---|---|
| `validate(string)` | `"type": "string"` | `string` |
| `validate(integer)` | `"type": "integer"` | `number` |
| `validate(float)` / `validate(number)` | `"type": "number"` | `number` |
| `validate(boolean)` | `"type": "boolean"` | `boolean` |
| `validate(map)` | `"type": "object"` | `Record<string, any>` |
| `validate(list)` | `"type": "array"` | `any[]` |
| `validate(max_len=N)` | `maxLength: N` (string) / `maxItems: N` (array) / `maximum: N` (number) | — |
| `validate(min_len=N)` | similar `min*` constraints | — |
| `validate(url)` | `"format": "uri"` | — |
| `validate(uuid)` | `"format": "uuid"` | — |
| `validate(email_r)` / `email` | `"format": "email"` | — |
| `validate(date)` | `"format": "date"` | — |
| `validate(datetime)` | `"format": "date-time"` | — |
| `validate(ipv4)` | `"format": "ipv4"` | — |
| `validate(regex=...)` | `"pattern": "..."` | — |
| `validate(enum=String[a::b])` | `"enum": ["a", "b"]` | `"a" \| "b"` |
| `validate(enum=Integer[1::2])` | `"enum": [1, 2]` | `number` |
| `enforce: true` | field name in `"required"` | non-optional |
| `default: v` | `"default": v` | — |

For sub_fields: schema recursively walks the auto-generated submodule and
inlines it. For `structs: true` sub_fields, emits `"type": "array"` with
`items` set to the submodule's schema.

---

## 2 · Mix tasks (Igniter-based)

> Under `lib/mix/tasks/`. All gracefully degrade if `:igniter` isn't loaded.

| Task | One-line description | Test |
|---|---|---|
| `mix guarded_struct.install` | Add dep, register `lint` alias, seed `derive_extensions: []` | `test/mix/tasks/guarded_struct.install_test.exs` |
| `mix guarded_struct.gen.struct` | Scaffold a starter module from CLI; `name!:type` syntax for enforce | `test/mix/tasks/guarded_struct.gen.struct_test.exs` |
| `mix guarded_struct.gen.schema` | Emit JSON Schema / TypeScript / OpenAPI for a module | `test/mix/tasks/guarded_struct.gen.schema_test.exs` |

### 2a · `mix guarded_struct.install`

```sh
# Bare install — adds dep + lint alias + seeds config :guarded_struct, derive_extensions: []
mix igniter.install guarded_struct

# With strict-mode flags — turns on compile-time op-name validation
mix igniter.install guarded_struct --strict          # strict_derive_ops: true
mix igniter.install guarded_struct --strict-paths    # strict_core_key_paths: true
```

### 2b · `mix guarded_struct.gen.struct`

```sh
mix guarded_struct.gen.struct MyApp.User name!:string age:integer email:email
# => creates lib/my_app/user.ex with:
#    field :name,  String.t(), enforce: true, derives: "validate(string)"
#    field :age,   integer(),                derives: "validate(integer)"
#    field :email, String.t(),               derives: "validate(email_r)"
```

The `name!:type` syntax (trailing `!`) marks the field `enforce: true`.

Supported type tokens: `string`, `integer`, `float`, `boolean`, `uuid`,
`email`, `url`, `date`, `datetime`, `map`, `list`, `any`. Each maps to a
`{type, derives:}` pair.

### 2c · `mix guarded_struct.gen.schema`

```sh
# JSON Schema (default format) printed to stdout
mix guarded_struct.gen.schema MyApp.User

# Write to file
mix guarded_struct.gen.schema MyApp.User --format=json --out=priv/user.json

# TypeScript interface
mix guarded_struct.gen.schema MyApp.User --format=typescript --out=apps/web/types/user.ts

# OpenAPI 3.1 components envelope
mix guarded_struct.gen.schema MyApp.User --format=openapi --out=priv/openapi/user.json
```

---

## 3 · Compile-time strict modes (opt-in config switches)

> Application-env switches, off by default for back-compat.

Two opt-in compile-time checks that turn silent runtime failures into
loud compile errors:

### `:strict_derive_ops`

> File: `lib/guarded_struct/transformers/verify_derive_ops.ex`
> Tests: `test/verify_derive_ops_test.exs`

Catches typos in `derives:` op names at compile time, with a
"did-you-mean" suggestion via `String.jaro_distance/2`. Auto-skipped if
a `derive_extensions:` plugin is configured (those can declare any
op name).

```elixir
# config/config.exs
config :guarded_struct, strict_derive_ops: true

# Then this becomes a compile error:
field :age, integer(), derives: "validate(intger)"
# ** (Spark.Error.DslError) unknown derive op(s) on field :age: validate=:intger
#    Did you mean `:integer`?
```

### `:strict_core_key_paths`

> File: `lib/guarded_struct/transformers/verify_core_key_paths.ex`
> Tests: `test/verify_core_key_paths_test.exs`

Verifies `from:` / `on:` paths reference real fields at compile time.

```elixir
config :guarded_struct, strict_core_key_paths: true

field :dest, String.t(), from: "root::nope"
# ** (Spark.Error.DslError) `from: "nope"` on field :dest references
#    `:nope`, which is not a declared field.
```

---

## 4 · Application env / configuration keys

| Key | One-line description |
|---|---|
| `derive_extensions: [Mod, ...]` | Custom-op modules registered via `Derive.Extension` |
| `strict_derive_ops: true` | Reject unknown derive ops at compile time |
| `strict_core_key_paths: true` | Reject unresolved `from:` / `on:` paths at compile time |
| `message_backend: Mod` | i18n backend module (Gettext, Cldr, or custom) |

```elixir
# config/config.exs
config :guarded_struct,
  derive_extensions: [MyApp.Derives],
  strict_derive_ops: true,
  strict_core_key_paths: true,
  message_backend: MyApp.GuardedStructMessages
```

Per-module override (via `use GuardedStruct, derive_extensions: [...]`)
is fixture-tested in `test/derive_extensions_per_module_test.exs`.

---

## 5 · Protocol consolidation tweak

> File: `mix.exs` — `consolidate_protocols: Mix.env() != :test`.

Disables protocol consolidation in the test env so test fixtures can
register `Jason.Encoder` implementations after the protocol set would
otherwise be frozen. Required for the `jason: true` opt to work in tests.

---

## 6 · Tooling integration

| Tool | One-line description |
|---|---|
| `mix lint` alias | Chains `mix spark.formatter` then `mix format` (seeded by installer) |
| `mix spark.formatter` | Works without `--extensions` flag — wired via mix alias |
| `mix spark.cheat_sheets` | Auto-generates `documentation/dsls/*.md` cheat sheets |
| `documentation/dsls/DSL-GuardedStruct.md` | Generated DSL cheat sheet |
| `documentation/dsls/DSL-GuardedStruct.AshResource.md` | Generated Ash-extension cheat sheet |
| `guidance/guarded-struct.livemd` | LiveBook tour with a "What's new in 0.1.0" section |
| `.formatter.exs` | `import_deps: [:spark]` so the `guardedstruct` block formats correctly |
| ElixirSense / Lexical autocomplete | Free via `Spark.ElixirSense.Plugin` (closes **#1**) |

---

## 7 · Dependencies added

> File: `mix.exs`.

| Dep | Scope | Why |
|---|---|---|
| `{:spark, "~> 2.7"}` | runtime | DSL extension framework |
| `{:splode, "~> 0.3"}` | runtime | Error class hierarchy |
| `{:telemetry, "~> 1.0"}` | runtime | Builder events |
| `{:igniter, "~> 0.8.0"}` | dev/test | Installer + scaffolder mix tasks |
| `{:sourceror, "~> 1.7"}` | dev/test | Source-mapping for installer |
| `{:stream_data, "~> 1.0"}` | test | Property-based parser tests |
| `{:jason, "~> 1.0"}` | test | `jason: true` opt-in test coverage |

Optional deps unchanged: `html_sanitize_ex`, `email_checker`, `ex_url`,
`ex_phone_number`, `sweet_xml`.

---

## 8 · Bug-fix highlights (release-note material)

- **`__information__/0`** now populates `conditional_keys` with the actual
  `conditional_field` names (was always `[]` in 0.0.x).
- All 14 orchestration-layer `Messages` callbacks (`required_fields`,
  `authorized_fields`, `builder`, `check_dependent_keys`, etc.) are
  reachable again — some were dead code in 0.0.x.
- `<MyMod>.Error.message/1` format matches master and uses
  `translated_message(:message_exception)` for i18n.
- Parser no longer crashes on invalid UTF-8 (`:binary.bin_to_list` +
  top-level rescue). Caught by `test/parser_property_test.exs`.
- `enum=Map[…]` / `equal=Map::…` operands are pre-evaluated at compile
  time — zero `Code.eval_string/1` calls in the runtime hot path.
- **`virtual_field` `derives:` now actually fires at runtime** (was
  silently dropped before `run_derives/2` in earlier 0.1.0 work; fixed
  via two-pass derive in `Runtime`).
