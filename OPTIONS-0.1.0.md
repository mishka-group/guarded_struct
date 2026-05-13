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
2. Application env / configuration keys
3. Protocol consolidation tweak
4. Tooling integration (`mix lint`, cheat sheets, LiveBook, autocomplete)
5. Dependencies added
6. Bug-fix highlights worth flagging on the release notes

---

## 1 · Mix task — `mix guarded_struct.install` (Igniter-based)

> File: `lib/mix/tasks/guarded_struct.install.ex`. Gracefully degrades if
> `:igniter` isn't loaded.
> Test: `test/mix/tasks/guarded_struct.install_test.exs`.

One-command project setup:

```sh
# Adds dep + lint alias + seeds config :guarded_struct, derive_extensions: []
mix igniter.install guarded_struct
```

What it does:
1. Adds `{:guarded_struct, "~> 0.1.0"}` to `mix.exs` deps (if not already)
2. Registers a `lint` alias chaining `mix spark.formatter` then `mix format`
3. Seeds `config :guarded_struct, derive_extensions: []` in `config/config.exs`
   so users have an obvious place to plug in custom validators

---

## 2 · Application env / configuration keys

| Key | One-line description |
|---|---|
| `derive_extensions: [Mod, ...]` | Custom-op modules registered via `Derive.Extension` |
| `message_backend: Mod` | i18n backend module (Gettext, Cldr, or custom) |

```elixir
# config/config.exs
config :guarded_struct,
  derive_extensions: [MyApp.Derives],
  message_backend: MyApp.GuardedStructMessages
```

Per-module override (via `use GuardedStruct, derive_extensions: [...]`)
is fixture-tested in `test/derive_extensions_per_module_test.exs`.

---

## 3 · Protocol consolidation tweak

> File: `mix.exs` — `consolidate_protocols: Mix.env() != :test`.

Disables protocol consolidation in the test env so test fixtures can
register `Jason.Encoder` implementations after the protocol set would
otherwise be frozen. Required for the `jason: true` opt to work in tests.

---

## 4 · Tooling integration

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

## 5 · Dependencies added

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

## 6 · Bug-fix highlights (release-note material)

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
