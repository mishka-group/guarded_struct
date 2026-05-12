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

1. Mix tasks (installer + scaffolder)
2. Compile-time strict modes (config-level switches)
3. Application env / configuration keys
4. Protocol consolidation tweak
5. Tooling integration (`mix lint`, cheat sheets, LiveBook, autocomplete)
6. Dependencies added
7. Bug-fix highlights worth flagging on the release notes

---

## 1 · Mix tasks (Igniter-based)

> Under `lib/mix/tasks/`. All gracefully degrade if `:igniter` isn't loaded.

| Task | One-line description | Test |
|---|---|---|
| `mix guarded_struct.install` | Add dep, register `lint` alias, seed `derive_extensions: []` | `test/mix/tasks/guarded_struct.install_test.exs` |
| `mix guarded_struct.gen.struct` | Scaffold a starter module from CLI; `name!:type` syntax for enforce | `test/mix/tasks/guarded_struct.gen.struct_test.exs` |

### 1a · `mix guarded_struct.install`

```sh
# Bare install — adds dep + lint alias + seeds config :guarded_struct, derive_extensions: []
mix igniter.install guarded_struct

# With strict-mode flags — turns on compile-time op-name validation
mix igniter.install guarded_struct --strict          # strict_derive_ops: true
mix igniter.install guarded_struct --strict-paths    # strict_core_key_paths: true
```

### 1b · `mix guarded_struct.gen.struct`

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

---

## 2 · Compile-time strict modes (opt-in config switches)

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

## 3 · Application env / configuration keys

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

## 4 · Protocol consolidation tweak

> File: `mix.exs` — `consolidate_protocols: Mix.env() != :test`.

Disables protocol consolidation in the test env so test fixtures can
register `Jason.Encoder` implementations after the protocol set would
otherwise be frozen. Required for the `jason: true` opt to work in tests.

---

## 5 · Tooling integration

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

## 6 · Dependencies added

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

## 7 · Bug-fix highlights (release-note material)

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
