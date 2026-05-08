# GuardedStruct → Spark: Re-Architecture Plan

> **Status:** design document, not yet implemented.
> **Audience:** the maintainer (you) and any future contributor.
> **Scope:** rewrite the entire `guarded_struct` library on top of [Spark DSL](https://hexdocs.pm/spark) so the long-standing compile-time problems disappear and the unfinished features (nested `conditional_field`, dynamic keys, virtual fields, mix schema generator, …) become trivial to land.

This file is intentionally long. Read it once end-to-end before touching code. Sections are independent enough to skim later. Every claim has a pointer to either the current source file or a Spark hexdoc reference.

---

## Table of Contents

1. [Executive summary](#1-executive-summary)
2. [Why we are rewriting](#2-why-we-are-rewriting)
3. [Hard limits of the current macro design](#3-hard-limits-of-the-current-macro-design)
4. [Full feature inventory (what must keep working)](#4-full-feature-inventory-what-must-keep-working)
5. [Mapping every open / closed issue onto the rewrite](#5-mapping-every-open--closed-issue-onto-the-rewrite)
6. [Spark primer (just enough)](#6-spark-primer-just-enough)
7. [The new architecture at a glance](#7-the-new-architecture-at-a-glance)
8. [DSL → Spark mapping (table)](#8-dsl--spark-mapping-table)
9. [Recursive entities — `sub_field` and nested `conditional_field`](#9-recursive-entities--sub_field-and-nested-conditional_field)
10. [The compile-time `derive` pipeline (the win you specifically asked for)](#10-the-compile-time-derive-pipeline)
11. [Module generation strategy](#11-module-generation-strategy)
12. [Runtime `builder/2` pipeline](#12-runtime-builder2-pipeline)
13. [Error paths and `DslError`](#13-error-paths-and-dslerror)
14. [Migration / delivery plan in phases](#14-migration--delivery-plan-in-phases)
15. [Test strategy and how the existing 6,300 LOC of tests are reused](#15-test-strategy)
16. [What Spark cannot do (and how we work around each)](#16-what-spark-cannot-do)
17. [Open questions / decisions to confirm](#17-open-questions)
18. [Appendix A — the new module layout](#appendix-a)
19. [Appendix B — quick Spark dep / mix.exs change](#appendix-b)
20. [Appendix C — references](#appendix-c)

---

## 1. Executive summary

`guarded_struct` today is ~4,700 lines of hand-written `defmacro`, `Module.put_attribute(:gs_*, accumulate: true)` accumulators, and a `@before_compile {__MODULE__, :create_builder}` callback that walks those accumulators to emit a `builder/2` function. It works. It also has three structural problems that block the roadmap:

1. **Nested `conditional_field` is impossible under the current AST-rewriting Parser.** `lib/derive/parser.ex:40` and `:56` literally `raise(translated_message(:unsupported_conditional_field))` whenever the DSL tries to nest one. This is the issue you call out by name — issues #7, #8, #25 — and it is the single biggest reason the project stalled.
2. **Compile-time validation is shallow.** `derive: "sanitize(trim) validate(string)"` is a *string*. We don't parse it until somebody calls `builder/2` at runtime. A typo (`"sanitize(trimm)"`) compiles cleanly, then fails on the first request, possibly in production.
3. **Errors point at macro internals, not the user's source.** When something does fail at compile time, the stack trace lands inside `Module.eval_quoted` calls in `register_struct/4`, not on the offending DSL line.

Spark fixes all three by giving us:

- **Recursive entities** — `sub_field` containing `sub_field` containing `conditional_field` containing `sub_field` is just `recursive_as: :sub_fields` and `recursive_as: :conditional_fields`. No macro recursion. No `Code.string_to_quoted!` of the user's block.
- **Transformers** that run between "DSL parsed" and "module compiled" and can rewrite the DSL state, including parsing the `derive:` mini-language once at compile time.
- **`Spark.Error.DslError`** with `path:`, `module:`, and per-option source `anno` (file/line/column) for editor-grade error messages.
- **Verifiers** that run *after* compile, with no compile-time deps, ideal for "validator MFA exists", "from path resolves", etc.

The deliverable is a drop-in replacement: same public API (`use GuardedStruct`, `guardedstruct do … end`, same `field` / `sub_field` / `conditional_field` syntax, same `builder/2` return shape), all 6,300 LOC of existing tests passing unchanged, **plus** the unfinished features.

---

## 2. Why we are rewriting

You wrote it best in `lib/messages.ex:284-293`:

```text
Unfortunately, this macro does not support the nested mode in the conditional_field macro.
If you can add this feature I would be very happy to send a PR.
More information: https://github.com/mishka-group/guarded_struct/issues/7
Parent Issue: https://github.com/mishka-group/guarded_struct/issues/8
```

That comment, plus your statement *"it is not good in compile time and i can not create nested use of macro"*, is the spec for this rewrite. We are rewriting because:

- The macro you wrote is at the limit of what hand-rolled `defmacro` can sanely express. To go further you need a DSL framework.
- The features you want next (nested conditional, dynamic keys, virtual fields, schema generator) all require introspecting the DSL tree at compile time. Spark *is* that introspection.
- The features you have already shipped (derive, sanitizer, validator, core keys) are runtime-heavy and would benefit from being moved to compile time. Spark *is* that move.
- The library is in "low maintenance" mode (see README.md:7-9) — a clean foundation makes contributions tractable for outsiders.

---

## 3. Hard limits of the current macro design

These are not opinions. They are the specific places in `lib/guarded_struct.ex` and `lib/derive/parser.ex` where the design has run out of room.

### 3.1. Twelve module attributes accumulated by side-effect

`lib/guarded_struct.ex:53-66`:

```elixir
@temporary_revaluation [
  :gs_fields, :gs_sub_fields, :gs_types, :gs_enforce_keys,
  :gs_validator, :gs_main_validator, :gs_derive,
  :gs_authorized_fields, :gs_external, :gs_core_keys,
  :gs_conditional_fields, :gs_caller
]
```

Every `field`/`sub_field`/`conditional_field` macro call mutates one or more of these via `Module.put_attribute(:gs_X, accumulate: true)`. The `@before_compile` callback in `register_struct/4:1535` then walks all twelve. This is fragile because:

- Order of macro calls inside the user's block matters. There is no way to say "rejected this `field` because its `:on` references a sibling that comes later". You'd have to read the future.
- If a single macro call raises, half the attributes are populated and `__before_compile__` runs against a corrupt state.
- The `delete_temporary_revaluation` callback at line 1428 wipes them after compile so introspection at runtime is impossible without `__information__/0` capturing them in closures.

Spark replaces all twelve with one `dsl_state` map, populated declaratively, walked deterministically by transformers ordered via `before?`/`after?`.

### 3.2. The conditional-field AST hijack

`lib/derive/parser.ex:28-72`:

```elixir
def parser(blocks, :conditional, parent \\ "root") do
  case blocks do
    {:__block__, line, items} ->
      {:__block__, line, elements_unification(items, parent)}
    {:field, line, items} ->
      {:field, line, add_parent_tags(items, parent)}
    {:sub_field, line, items} ->
      {:sub_field, line, add_parent_tags(items, parent)}
    {:conditional_field, line, items} ->
      raise(translated_message(:unsupported_conditional_field))   # <-- the dead end
      ...
  end
end
```

The current implementation literally walks the user's quoted AST and tags each child with a synthesized `__node_id__` so `Derive.derive/1` can correlate hint/derive/validator with the right child at runtime. To support nesting we'd have to do this recursion inside an outer recursion, propagate the IDs up *and* down, and reconcile errors across levels. That is what Spark's `recursive_as` does for free.

### 3.3. `defmodule` inside `quote` inside `defmacro`

`sub_field/4:1300-1318` does:

```elixir
defmacro sub_field(name, type, opts \\ [], do: block) do
  ast = register_struct(block, opts, name, __CALLER__.module)
  ...
  quote do
    %{name: module_name, ...} = GuardedStruct.sub_conditional_field_module(...)
    GuardedStruct.__field__(...)
    defmodule module_name do
      unquote(ast)
      if unquote(is_error), do: GuardedStruct.create_error_module()
    end
  end
end
```

Generating a module from inside a macro that is itself called inside another macro produces stacked `Module.eval_quoted` frames. The error backtrace from a failing nested `sub_field` is unreadable. Spark `Module.create` from a transformer (with a real `Macro.Env.location`) gives clean traces and runs once per submodule deterministically.

### 3.4. String DSL parsed at every runtime invocation

`lib/derive/parser.ex:9-26` parses `"sanitize(trim) validate(string, max_len=20)"` via `Code.string_to_quoted!` *every* `builder/2` call. The result is the same every time. There is no cache. There is no compile-time validation. A typo lands in production. We can fix this without Spark, but with Spark the fix is the natural shape (a transformer pass) and the error-on-typo lands at `mix compile` time with file:line:column.

### 3.5. Error backtraces

Try this in a test file:

```elixir
guardedstruct do
  field(:name, "not a type, this is a string", derive: "validate(string)")
end
```

The error comes from inside `Macro.escape` deep in `register_struct/4`. There is no pointer to the user's file. Spark's `Spark.Error.DslError` with `path:` and `anno:` gives `myfile.ex:42:14: field :name -> type: expected an atom, got "not a type"`.

### 3.6. No formatter / autocomplete / docs

Today users have to hand-maintain `locals_without_parens` for `field`, `sub_field`, `conditional_field`. Editor autocomplete inside `guardedstruct do … end` is dead. Docs are hand-written in the `@moduledoc`. Spark gives all three for free (`mix spark.formatter`, `Spark.ElixirSense.Plugin`, `mix spark.cheat_sheets`).

### 3.7. Issue references

The library tells you these limits already exist:

- `lib/messages.ex:284-293` — nested conditional fields explicitly unsupported (#7, #8).
- `test/nested_conditional_field_test.exs:1-9` — entire test file commented out citing #23, #25.
- `test/nested_sub_field_test.exs:1-5` — comments out tests citing #7, #12.
- `lib/guarded_struct.ex:2271-2293` — long block-comment explaining why list-of-list of normal fields doesn't work and asking for a PR.

The rewrite addresses every one.

---

## 4. Full feature inventory (what must keep working)

If a feature appears anywhere below, a test exists for it under `test/`. The rewrite must keep the feature **and** the test green.

### 4.1. Top-level options on `guardedstruct do … end`

| Option | Behaviour | Where it's tested |
| --- | --- | --- |
| `enforce: true` | Every field is `enforce` unless overridden | `basic_types_test.exs:36-77` |
| `opaque: true` | Generates `@opaque t()` instead of `@type t()` | `basic_types_test.exs:91-95` |
| `module: SubName` | Wraps the whole struct in `defmodule SubName` | `basic_types_test.exs:47-53` |
| `error: true` | Generates a `defexception` `<Mod>.Error` | `global_test.exs:317-336` |
| `authorized_fields: true` | Reject unknown keys instead of dropping them | `core_keys_test.exs:101-133`, `global_test.exs:339-379` |
| `main_validator: {Mod, :fn}` | Whole-output validation pass | `validator_derive_test.exs:179-198, 306-332` |
| `validate_derive: Mod | [Mod]` | Pluggable derive registry | `derive_test.exs:704-739` |
| `sanitize_derive: Mod | [Mod]` | Pluggable sanitizer registry | `derive_test.exs:704-739` |

### 4.2. The `field/3` macro options

```elixir
field(:name, type, opts)
```

Every option below comes from `lib/guarded_struct.ex` plus `test/`:

- `enforce: true` (`required_fields/2:1667`)
- `default: term` (`config(:fields_types):2168`)
- `derive: "..."` — sanitize+validate mini-language, see §10
- `validator: {Mod, :fn}` (`get_field_validator/4:2736`)
- `auto: {Mod, :fn}` or `{Mod, :fn, default}` — generated value, optionally dependent on `:edit` mode (`auto_core_key/3:1688`)
- `from: "root::path"` or `"sibling::path"` — copy from another field (`from_core_key/1:1755`)
- `on: "root::path"` — required-if-this-other-key-present (`on_core_key/2:1744` + `check_dependent_keys/3:2368`)
- `domain: "!path=Type[a, b]::?path=…"` — input-shape constraints with `!` (required) and `?` (optional) (`domain_core_key/2:1716`, `parse_domain_patterns/4:2475`)
- `struct: AnotherMod` — embed another `guardedstruct` module by reference (one) (`get_fields_sub_module/4:2047`)
- `structs: AnotherMod` or `structs: true` — embed list of structs (`list_builder/6:2295`)
- `hint: "label"` — surfaces in conditional-field error output (`add_hint/2:2729`)
- `priority: true` (only inside `conditional_field`) — short-circuit on first match (`separate_conditions_based_priority/3:2563`)

### 4.3. The `sub_field/4` macro

```elixir
sub_field(:name, struct(), opts) do
  field(:inner, …)
  sub_field(:deeper, …) do … end
  conditional_field(:choose, …) do … end
end
```

- Generates a real `defmodule <Parent>.<CamelizedName>` with its own `builder/2`, `keys/0`, `enforce_keys/0`, `__information__/0`, `defstruct`, `t()` typespec.
- All of `field`'s options work on the sub_field (enforce, derive, validator, struct, structs, error, authorized_fields).
- `structs: true` makes the sub_field a list-of-this-shape (`sub_modules_builders` branch in `sub_fields_validating/7:1802`).

### 4.4. The `conditional_field/4` macro

```elixir
conditional_field(:address, any(), structs: true, priority: true, on: "root::x") do
  field(:address, String.t(), validator: {VAL, :is_string_data}, hint: "addr1")
  sub_field(:address, struct(), validator: {VAL, :is_map_data}, hint: "addr2") do
    field(:lat, String.t())
  end
  field(:address, struct(), structs: ExternalMod, validator: {VAL, :is_list_data}, hint: "addr3")
end
```

- Multiple children all share the same `:name`.
- At runtime the first child whose `:validator` returns `{:ok, …}` wins.
- Children may be `field`, `sub_field`, or external `struct:` / `structs:` references.
- Top-level `structs: true` means the whole conditional accepts a list of values; each list item is matched independently.
- `priority: true` short-circuits on the first match (no later validators run).
- `derive:` on the conditional itself runs against every input value before child matching.
- `on:` / `from:` / `auto:` / `domain:` all work on the conditional itself.
- **Nested `conditional_field` inside `conditional_field` is currently not supported** — this is the unfinished feature this rewrite enables.

### 4.5. The runtime `builder/2`

`lib/guarded_struct.ex:1582-1629` defines the pipeline. Every step has a test:

```
builder(attrs, error?)
  → before_revaluation        # extract from {:root, attrs} or {key_path, attrs}
  → authorized_fields         # reject unknown keys when authorized_fields: true
  → required_fields           # missing enforce keys → halt
  → Parser.convert_to_atom_map
  → auto_core_key             # apply auto-generated values
  → domain_core_key           # check parent-driven cross-field constraints
  → on_core_key               # check on:/dependent_keys constraints
  → from_core_key             # apply from-copy
  → conditional_fields_validating
  → sub_fields_validating     # recurse into each sub_field's builder/2
  → fields_validating         # per-field validator
  → main_validating           # whole-output main_validator
  → replace_condition_fields_derives
  → Derive.derive             # apply sanitize then validate
  → exceptions_handler        # raise <Mod>.Error if requested
```

Each step accepts `{:ok, …}` and is a no-op on `{:error, _, :halt}`. The rewrite preserves this exact pipeline order in `GuardedStruct.Runtime.build/3` (a runtime helper, no longer a macro).

### 4.6. Generated functions on every produced module

Every module that uses `guardedstruct` (root or sub) must expose:

- `defstruct ...`
- `@type t() :: %__MODULE__{...}` (or `@opaque`)
- `@enforce_keys [...]`
- `def builder/2`, `def builder/3`
- `def keys/0`, `def keys(:all)`, `def keys(field)`
- `def enforce_keys/0`, `def enforce_keys(:all)`, `def enforce_keys(field)`
- `def __information__/0`

### 4.7. The derive mini-language

40+ built-in derives, three categories:

- `sanitize(...)` — string transforms (`trim`, `upcase`, `basic_html`, `tag=strip_tags`, `string_float`, …).
- `validate(...)` — type and constraint checks (`string`, `integer`, `max_len=N`, `email`, `enum=String[a::b]`, `regex='…'`, `equal=Type::value`, `either=[v1, v2]`, `custom=[Mod, fn]`, …).
- Pluggable extensions via `validate_derive` / `sanitize_derive` config.

Full list and their dependencies are in `README.md:319-393`.

### 4.8. Configurable message backend

`lib/messages.ex` defines a `@callback`-based backend. Users can swap to gettext via `config :guarded_struct, message_backend: MyApp.Messages` (closed issue #10). The rewrite preserves this verbatim — Spark only touches compile time, not the runtime message dispatch.

---

## 5. Mapping every open / closed issue onto the rewrite

| # | Status today | Title | Where it lands in the rewrite |
| --- | --- | --- | --- |
| #1 | OPEN | VS Code extension for autocomplete | **Free** with Spark — `Spark.ElixirSense.Plugin` gives autocomplete in ElixirLS / Lexical out of the box. No work. |
| #2 | OPEN | Single-validation API (use one validator standalone) | Trivial: expose `GuardedStruct.Validate.run/3` that takes a derive op-list and a value. Built on the same parsed-at-compile-time op-list. |
| #3 | OPEN | `mix` schema file generator | `mix guarded_struct.gen.schema MyApp.Resource` walks the DSL state via the Info module and emits JSON Schema / TypeScript / OpenAPI. Easy because Spark has a structured DSL state, unlike module attributes. |
| #4 | OPEN | More predefined validations / sanitizers | Add new entries to `GuardedStruct.Derive.Validate` and `Sanitize`. Same pattern as today; just lives in modules instead of in the giant `case` in `validation_derive.ex`. |
| #5 | OPEN | Virtual field | Add a new entity `virtual_field` next to `field`. Marked with `virtual: true` on the entity struct. Excluded from `defstruct` codegen but included in the validation pipeline. ~30 lines of transformer logic. |
| #6 | OPEN | Erlang Records inside `guardedstruct` | Add `:record` as a new accepted `:type` plus a small `Record` derive. Compatibility with erlang `:queue` is already there (`validate(:queue)`); this generalizes it. |
| #7 | CLOSED (workaround) | Nested conditional fields | **First-class.** `conditional_field` becomes a Spark entity with `recursive_as: :conditional_fields`. The `unsupported_conditional_field` error message is deleted. See §9. |
| #8 | CLOSED | Predefined validations 0.1.4 | Subsumed by #4. |
| #10 | CLOSED | i18n / l10n support | Already shipped; keep as-is. |
| #11 | OPEN | Dynamic key support | New entity `dynamic_field` (or option `dynamic: true` on `field`) — generates a struct that allows `Map.put/3` of keys not declared at compile time, validated against a generic schema. ~50 lines of transformer + runtime work. |
| #12 | OPEN | Nested-list validation issues | Naturally fixed by recursive entities — list-of-list of `sub_field`s composes via `recursive_as`. The block comment at `guarded_struct.ex:2271-2293` becomes obsolete. |

Net effect: every open issue gets a clear path; every closed issue is preserved.

---

## 6. Spark primer (just enough)

A condensed version of the full Spark research. If you want the long version, ask for it; this is what you actually need to read the rest of this doc.

### 6.1. The five core abstractions

| Module | Role | Runs at |
| --- | --- | --- |
| `Spark.Dsl` | The `use`-able DSL the user adopts (`use GuardedStruct`). | Compile time of user module |
| `Spark.Dsl.Extension` | A bundle of `sections`, `transformers`, `verifiers`, `persisters`. We ship one: `GuardedStruct.Dsl`. | Compile time |
| `Spark.Dsl.Section` | A `do … end` block name. Has options + entities. We have one section: `:guardedstruct`. | Definition data |
| `Spark.Dsl.Entity` | A struct constructor inside a section (`field`, `sub_field`, `conditional_field`). | Definition data |
| `Spark.Dsl.Transformer` | Pure `dsl_state -> {:ok, dsl_state'}` pass. Mutates DSL state, can `eval/3` quoted code into the user's module, can `Module.create/3` submodules. | Compile time, before module body finishes |
| `Spark.Dsl.Verifier` | Pure `dsl_state -> :ok | {:error, _}` check. Read-only. | **After** module compiled |
| `Spark.InfoGenerator` | `use`-able helper that emits typed accessors on `MyLib.Info`. | Compile time of `Info` module |

### 6.2. The contract you implement

```elixir
defmodule GuardedStruct do
  use Spark.Dsl,
    default_extensions: [extensions: [GuardedStruct.Dsl]]
end

defmodule GuardedStruct.Dsl do
  @field    %Spark.Dsl.Entity{name: :field,    target: ..., schema: ..., args: [:name, :type]}
  @sub_field %Spark.Dsl.Entity{name: :sub_field, target: ..., recursive_as: :sub_fields,
                                entities: [fields: [@field], conditional_fields: []]}
  @conditional_field %Spark.Dsl.Entity{name: :conditional_field, ..., recursive_as: :conditional_fields,
                                        entities: [fields: [@field], sub_fields: [@sub_field]]}

  @section %Spark.Dsl.Section{
    name: :guardedstruct,
    top_level?: true,
    schema: [...],
    entities: [@field, @sub_field, @conditional_field]
  }

  use Spark.Dsl.Extension,
    sections: [@section],
    transformers: [
      GuardedStruct.Transformers.ParseDerive,
      GuardedStruct.Transformers.ParseCoreKeys,
      GuardedStruct.Transformers.GenerateBuilder,
      GuardedStruct.Transformers.GenerateSubFieldModules
    ],
    verifiers: [
      GuardedStruct.Verifiers.VerifyConditionalChildrenShareName,
      GuardedStruct.Verifiers.VerifyValidatorMFA,
      GuardedStruct.Verifiers.VerifyAutoMFA,
      GuardedStruct.Verifiers.VerifyFromPath,
      GuardedStruct.Verifiers.VerifyOnPath,
      GuardedStruct.Verifiers.VerifyDomainExpressions
    ]
end
```

That's the complete public surface. Everything else is implementation.

### 6.3. Important Spark APIs you'll use

- `Spark.Dsl.Transformer.get_entities(dsl, [:guardedstruct])` — list of entity structs at a section path.
- `Spark.Dsl.Transformer.get_option(dsl, [:guardedstruct], :enforce)` — section option.
- `Spark.Dsl.Transformer.get_persisted(dsl, key)` — read from a transformer-only cache.
- `Spark.Dsl.Transformer.persist(dsl, key, value)` — write to that cache.
- `Spark.Dsl.Transformer.replace_entity(dsl, path, new_entity, fn old -> ... end)` — swap an entity.
- `Spark.Dsl.Transformer.add_entity(dsl, path, new_entity)` — append.
- `Spark.Dsl.Transformer.eval(dsl, bindings, quoted)` — inject quoted code into the user's module.
- `Spark.Dsl.Transformer.async_compile(dsl, fn -> Module.create(...) end)` — generate a submodule in parallel.
- `Spark.Dsl.Entity.anno/1`, `Spark.Dsl.Entity.property_anno/2` — `{file, line, column}` for editor-grade errors.
- `Spark.Error.DslError.exception(message:, path:, module:)` — the error you raise from transformers/verifiers.

### 6.4. Tooling you get free

- `mix spark.formatter --extensions GuardedStruct.Dsl` — auto-maintains `spark_locals_without_parens` in `.formatter.exs`.
- `mix spark.cheat_sheets --extensions GuardedStruct.Dsl` — markdown reference for ExDoc.
- `Spark.ElixirSense.Plugin` — autocomplete for editors (closes issue #1).
- `mix spark.replace_doc_links` — rewrites `d:Module.section.entity` in docs.

### 6.5. Versions

- Latest stable: `spark ~> 2.7`.
- Minimum Elixir: `~> 1.15` (you're on 1.17, fine).
- Dep line: `{:spark, "~> 2.7"}`.

---

## 7. The new architecture at a glance

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          USER MODULE (e.g. MyApp.User)                       │
│                                                                              │
│   defmodule MyApp.User do                                                    │
│     use GuardedStruct                                                        │
│     guardedstruct enforce: true do                                           │
│       field :id, :integer, derive: "validate(integer)"                       │
│       sub_field :auth, :map do                                               │
│         field :token, :string                                                │
│         conditional_field :role, :any do                                     │
│           field :role, :string, validator: {V, :is_str}, hint: "as_string"   │
│           sub_field :role, :map, hint: "as_object" do                        │
│             field :name, :string                                             │
│             conditional_field :tier, :any do        ⬅︎ NESTED CONDITIONAL    │
│               field :tier, :integer                                          │
│               field :tier, :string                                           │
│             end                                                              │
│           end                                                                │
│         end                                                                  │
│       end                                                                    │
│     end                                                                      │
│   end                                                                        │
└──────────────────────────────────────────────────────────────────────────────┘
                                        │
                  ┌─────────────────────┴────────────────────────┐
                  │                                              │
                  ▼                                              ▼
   ┌────────────────────────┐                   ┌────────────────────────────────┐
   │  Spark builds DSL state │                   │  GuardedStruct.Dsl Extension  │
   │  (entity tree)          │ ◀──── reads ────  │  - sections: [@section]       │
   │                         │                   │  - transformers: […]          │
   │  %{                     │                   │  - verifiers: […]             │
   │    [:guardedstruct] =>  │                   └────────────────────────────────┘
   │      %Section{          │
   │        opts: %{enforce: true},
   │        entities: [
   │          %Field{name: :id, derive: "validate(integer)"},
   │          %SubField{name: :auth,
   │            fields: [%Field{name: :token, …}],
   │            conditional_fields: [
   │              %ConditionalField{name: :role,
   │                fields: [%Field{name: :role, hint: "as_string", …}],
   │                sub_fields: [
   │                  %SubField{name: :role, hint: "as_object",
   │                    fields: [%Field{name: :name, …}],
   │                    conditional_fields: [
   │                      %ConditionalField{name: :tier,    ⬅︎ NESTED!
   │                        fields: [%Field{name: :tier, type: :integer},
   │                                 %Field{name: :tier, type: :string}],
   │                        sub_fields: []
   │                      }]
   │                    }]
   │                  }]
   │                }]
   │            }]
   │        ]
   │      }
   │  }                       │
   └─────────────┬────────────┘
                 │
                 ▼
   ┌────────────────────────────────────────────────────────────────────────────┐
   │ TRANSFORMERS (run in topo order)                                          │
   │ 1. ParseDerive          — replace string `derive:` with normalized op-list │
   │ 2. ParseCoreKeys        — split "root::a::b" into [:root, :a, :b]         │
   │ 3. ParseDomainExpr      — normalize "!path=Type[…]" into {:require, …}    │
   │ 4. NormalizeConditional — assign synthetic ChildN module names            │
   │ 5. GenerateBuilder      — eval/3 builder/keys/enforce_keys/__information__│
   │ 6. GenerateSubModules   — Module.create per sub_field, async_compile      │
   │ 7. GenerateErrorModules — Module.create per `error: true` level           │
   └────────────────────────────────────────────────────────────────────────────┘
                 │
                 ▼
   ┌────────────────────────────────────────────────────────────────────────────┐
   │ MODULE COMPILES (with all the eval/3 quoted blocks injected)              │
   └────────────────────────────────────────────────────────────────────────────┘
                 │
                 ▼
   ┌────────────────────────────────────────────────────────────────────────────┐
   │ VERIFIERS (post-compile, no compile deps)                                 │
   │ - ConditionalChildrenShareName                                             │
   │ - ValidatorMFAExists                                                       │
   │ - AutoMFAExists                                                            │
   │ - FromPathResolves                                                         │
   │ - OnPathResolves                                                           │
   │ - DomainExpressionTypeChecks                                               │
   └────────────────────────────────────────────────────────────────────────────┘
                 │
                 ▼
       Compiled module ready for runtime.
                 │
                 │   builder(attrs, error?)
                 ▼
   ┌────────────────────────────────────────────────────────────────────────────┐
   │ GuardedStruct.Runtime.build/3                                             │
   │ (pure runtime, reads from compiled artifacts, no DSL knowledge)            │
   │                                                                            │
   │ Pipeline (same as today):                                                  │
   │   normalize attrs → authorized_fields → required → auto → domain → on →    │
   │   from → conditional → sub_fields → fields → main → replace_cond_derives → │
   │   derive (sanitize → validate) → exceptions_handler                        │
   └────────────────────────────────────────────────────────────────────────────┘
```

The user-facing DSL is unchanged. The internals — every line of `lib/guarded_struct.ex` — are replaced by Spark machinery + a thin runtime.

---

## 8. DSL → Spark mapping (table)

| Current DSL | Current implementation | New implementation |
| --- | --- | --- |
| `use GuardedStruct` | `defmacro __using__/1` imports `guardedstruct/1,2` | `use Spark.Dsl, default_extensions: [extensions: [GuardedStruct.Dsl]]` |
| `guardedstruct opts do … end` | `defmacro guardedstruct/2` calls `register_struct/4` | `Spark.Dsl.Section{name: :guardedstruct, top_level?: true, schema: [enforce, opaque, module, error, authorized_fields, main_validator, validate_derive, sanitize_derive]}` |
| `field :name, type, opts` | `defmacro field/3` → `__field__/6` → `Module.put_attribute(:gs_fields, …)` | `Spark.Dsl.Entity{name: :field, target: %Field{}, args: [:name, :type], schema: [...]}` |
| `sub_field :name, type, opts do … end` | `defmacro sub_field/4` → `register_struct/4` recursive + `defmodule` inside `quote` | `Spark.Dsl.Entity{name: :sub_field, target: %SubField{}, args: [:name, :type], recursive_as: :sub_fields, entities: [fields: [@field], conditional_fields: [@conditional_field]]}` |
| `conditional_field :name, type, opts do … end` | `defmacro conditional_field/4` → `Parser.parser(block, :conditional)` (raises on nesting) | `Spark.Dsl.Entity{name: :conditional_field, target: %ConditionalField{}, recursive_as: :conditional_fields, entities: [fields: [@field], sub_fields: [@sub_field]]}` |
| `derive: "sanitize(trim) validate(string)"` | Parsed at every `Derive.derive/1` call via `Code.string_to_quoted!` | Parsed once at compile time by `GuardedStruct.Transformers.ParseDerive`, stored as `[{:sanitize, :trim}, {:validate, :string}]` on the entity |
| `validator: {Mod, :fn}` | Validated at runtime inside `find_validator/4` | Stored as-is; `GuardedStruct.Verifiers.VerifyValidatorMFA` checks `function_exported?` post-compile |
| `auto: {Mod, :fn, default}` | Validated at runtime inside `auto_core_key/3` | Stored as-is; `GuardedStruct.Verifiers.VerifyAutoMFA` checks post-compile |
| `from: "root::path"` / `on: "root::path"` | Parsed at runtime via `Parser.parse_core_keys_pattern/1` | Parsed at compile time by `GuardedStruct.Transformers.ParseCoreKeys` into `[:root, :path]`; `GuardedStruct.Verifiers.VerifyFromPath` / `VerifyOnPath` check the path resolves |
| `domain: "!auth.action=String[admin, user]::?auth.social=Atom[banned]"` | Parsed at runtime via `parse_domain_patterns/4` | Parsed at compile time by `GuardedStruct.Transformers.ParseDomainExpr` into structured tuples; `VerifyDomainExpressions` type-checks |
| `struct: AnotherMod` / `structs: AnotherMod` | Stored on `:gs_external` accumulator | Stored on the entity directly; verified to be a real module post-compile |
| `error: true` | `defmacro create_error_module/0` quoted into the parent | `GuardedStruct.Transformers.GenerateErrorModules` calls `Module.create` for `<Mod>.Error` |
| `main_validator: {Mod, :fn}` | Stored on `:gs_main_validator` accumulator | Stored as section option |
| `authorized_fields: true` | Stored on `:gs_authorized_fields` accumulator | Stored as section option (or per-sub_field as entity option) |
| `def builder/2`, `def keys/0`, `def enforce_keys/0`, `def __information__/0` | Generated by `defmacro create_builder/1` via `@before_compile` | Generated by `GuardedStruct.Transformers.GenerateBuilder` via `Spark.Dsl.Transformer.eval/3` |
| `defstruct …`, `@enforce_keys …`, `@type t() :: …` | Emitted by `register_struct/4` | Emitted by `GuardedStruct.Transformers.GenerateBuilder` (top-level) and `GuardedStruct.Transformers.GenerateSubFieldModules` (nested) via `eval/3` and `Module.create/3` respectively |

This is the entire mapping. Everything in `lib/guarded_struct.ex` either disappears or moves into one of these transformers/verifiers.

---

## 9. Recursive entities — `sub_field` and nested `conditional_field`

This section is here because you specifically asked. Nested `conditional_field` is the load-bearing feature this rewrite enables. The implementation is *one line* of Spark configuration.

### 9.1. The Spark recursion model

`recursive_as: <key>` on an entity tells Spark "inside this entity's `do … end`, the same set of macros (`field`, `sub_field`, `conditional_field`) is available, and the resulting child entities accumulate into `<key>` on the parent struct."

From `Spark.Dsl.Extension` source (paraphrased):

```elixir
case entity.recursive_as do
  nil -> entity
  recursive_as ->
    %{entity | entities: Keyword.put_new(entity.entities || [], recursive_as, [])}
end
```

So when we declare:

```elixir
@sub_field %Spark.Dsl.Entity{
  name: :sub_field,
  target: SubField,
  args: [:name, :type],
  schema: [name: [type: :atom, required: true], type: [type: :any, required: true], …],
  recursive_as: :sub_fields,
  entities: [
    fields: [@field],
    conditional_fields: [@conditional_field]
    # :sub_fields slot is added automatically by recursive_as
  ]
}
```

…we get, for free, the ability to nest `sub_field` to arbitrary depth, and inside any `sub_field` the user can also use `field` and `conditional_field`. Each child accumulates onto the right key (`fields`, `sub_fields`, `conditional_fields`).

### 9.2. Nested `conditional_field` (the unblocker)

```elixir
@conditional_field %Spark.Dsl.Entity{
  name: :conditional_field,
  target: ConditionalField,
  args: [:name, :type],
  schema: [
    name: [type: :atom, required: true],
    type: [type: :any, required: true],
    structs: [type: :boolean, default: false],
    priority: [type: :boolean, default: false],
    hint: [type: :string],
    derive: [type: :string],
    validator: [type: {:tuple, [:atom, :atom]}],
    auto: [type: :any],
    from: [type: :string],
    on: [type: :string],
    domain: [type: :string]
  ],
  recursive_as: :conditional_fields,           # ← THE LINE
  entities: [
    fields: [@field],
    sub_fields: [@sub_field]
    # :conditional_fields slot added automatically
  ]
}
```

That single `recursive_as: :conditional_fields` line replaces the `raise(translated_message(:unsupported_conditional_field))` in `lib/derive/parser.ex:40` and `:56`. Issues #7, #8, #25 close themselves.

### 9.3. The runtime story

A nested conditional_field at the DSL level becomes a recursive `%ConditionalField{}` struct in DSL state. The runtime evaluation then becomes a tree walk: when `GuardedStruct.Runtime.try_conditional/3` is iterating children of the outer conditional, and a child is itself a `%ConditionalField{}`, it recurses by calling itself. Pseudocode:

```elixir
def try_conditional(value, %ConditionalField{} = cond, ctx) do
  cond.fields
  |> Stream.concat(cond.sub_fields)
  |> Stream.concat(cond.conditional_fields)             # ← nested case
  |> Enum.find_value(:no_match, fn child ->
    case run_child(child, value, ctx) do
      {:ok, _} = ok -> ok
      {:error, _}    -> false
    end
  end)
end
```

Errors aggregate the same way as today; `hint:` from each child is preserved.

### 9.4. Verifier: children must share the parent's name

The current library implicitly relies on every child of a `conditional_field` declaring the same `:name` (because the runtime resolves on key name). We make this explicit:

```elixir
defmodule GuardedStruct.Verifiers.VerifyConditionalChildrenShareName do
  use Spark.Dsl.Verifier
  alias Spark.Dsl.Verifier

  def verify(dsl_state) do
    walk_conditionals(dsl_state, [:guardedstruct])
    |> Enum.find_value(:ok, fn cond ->
      bad_children =
        (cond.fields ++ cond.sub_fields ++ cond.conditional_fields)
        |> Enum.reject(&(&1.name == cond.name))

      if bad_children == [] do
        nil
      else
        {:error,
         Spark.Error.DslError.exception(
           message:
             "all children of conditional_field #{cond.name} must share its name; got #{inspect(Enum.map(bad_children, & &1.name))}",
           path: [:guardedstruct, :conditional_field, cond.name],
           module: Verifier.get_persisted(dsl_state, :module)
         )}
      end
    end)
  end

  defp walk_conditionals(dsl_state, path) do
    # depth-first walk, including nested conditionals
    ...
  end
end
```

Same pattern for any other invariant. Verifiers cost nothing at compile and produce great errors.

---

## 10. The compile-time `derive` pipeline

You called this out specifically. It's the single biggest runtime → compile-time win.

### 10.1. The status quo

Every call to `MyMod.builder(attrs)` triggers:

```elixir
# lib/derive/parser.ex:9-26
def parser(input) do
  String.split(String.trim(input), ")")
  |> Enum.reject(&(&1 == ""))
  |> Enum.map(fn x ->
    case Code.string_to_quoted!(String.trim(x) <> ")") do
      {key, _, parameters} -> convert_parameters(key, parameters)
      _ -> nil
    end
  end)
  ...
rescue
  _e -> nil   # silently swallows malformed derive strings
end
```

For every field, on every request. `Code.string_to_quoted!` is not free (think 10–100 µs per call). On a hot path with many fields it's measurable. Worse: the `rescue _e -> nil` means a malformed `derive:` becomes a silent `nil` and the field skips validation entirely. Typos ship to production.

### 10.2. The transformer

`GuardedStruct.Transformers.ParseDerive` runs once at compile time, walks every `%Field{}` and `%ConditionalField{}` in DSL state, and replaces the string `derive:` with a normalized op-list. It also raises `Spark.Error.DslError` on malformed derives, with file:line:column.

```elixir
defmodule GuardedStruct.Transformers.ParseDerive do
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  # Run before every transformer that consumes derive ops
  def before?(GuardedStruct.Transformers.GenerateBuilder), do: true
  def before?(GuardedStruct.Transformers.GenerateSubFieldModules), do: true
  def before?(_), do: false

  def transform(dsl_state) do
    {:ok,
     walk_entities(dsl_state, [:guardedstruct], fn entity ->
       case entity do
         %{derive: nil} ->
           entity

         %{derive: ops} when is_list(ops) ->
           # already parsed (idempotent in case of repeated runs)
           entity

         %{derive: str, name: field_name} = e when is_binary(str) ->
           case GuardedStruct.Derive.Compile.parse(str) do
             {:ok, ops} ->
               %{e | derive: ops}

             {:error, reason} ->
               raise Spark.Error.DslError,
                 message:
                   "invalid derive on field #{inspect(field_name)}: #{reason}\n" <>
                     "  string was: #{inspect(str)}",
                 path: [:guardedstruct, :field, field_name, :derive],
                 module: Transformer.get_persisted(dsl_state, :module)
           end
       end
     end)}
  end

  defp walk_entities(dsl_state, path, fun) do
    # walk top-level entities AND recurse into sub_fields' fields/sub_fields/conditional_fields
    # AND into conditional_fields' fields/sub_fields/conditional_fields
    ...
  end
end
```

`GuardedStruct.Derive.Compile.parse/1` is the moved-from-runtime version of the current `Parser.parser/1`, hardened to *return* `{:ok, ops}` or `{:error, reason}` instead of `rescue _ -> nil`. The shape of `ops`:

```elixir
[
  {:sanitize, :trim},
  {:sanitize, :upcase},
  {:validate, :string},
  {:validate, {:max_len, 20}},
  {:validate, {:min_len, 3}},
  {:validate, {:enum, {:string, ["admin", "user", "banned"]}}}
]
```

### 10.3. The runtime

`GuardedStruct.Derive.run/2` accepts a value and an op-list:

```elixir
def run(value, ops) do
  Enum.reduce_while(ops, {:ok, value}, fn
    {:sanitize, op}, {:ok, v} ->
      {:cont, {:ok, GuardedStruct.Derive.Sanitize.apply(op, v)}}

    {:validate, op}, {:ok, v} ->
      case GuardedStruct.Derive.Validate.apply(op, v) do
        {:ok, _} = ok -> {:cont, ok}
        {:error, _} = err -> {:halt, err}
      end
  end)
end
```

No parsing. No `Code.string_to_quoted!`. Pure pattern match dispatch. A loop-tight inner core. Easily benchmarked: expect ~10x speedup on field-heavy structs.

### 10.4. The validator (compile-time syntax check)

Even if you decide *not* to ship the parsing-as-transformer feature in v1, ship this verifier — it costs nothing and catches typos:

```elixir
defmodule GuardedStruct.Verifiers.VerifyDeriveSyntax do
  use Spark.Dsl.Verifier

  def verify(dsl_state) do
    walk_fields(dsl_state)
    |> Enum.find_value(:ok, fn field ->
      case field.derive do
        nil -> nil
        str when is_binary(str) ->
          case GuardedStruct.Derive.Compile.parse(str) do
            {:ok, _} -> nil
            {:error, reason} ->
              {:error,
               Spark.Error.DslError.exception(
                 message: "bad derive on #{field.name}: #{reason}",
                 path: [:guardedstruct, :field, field.name, :derive],
                 module: Spark.Dsl.Verifier.get_persisted(dsl_state, :module)
               )}
          end
      end
    end)
  end
end
```

### 10.5. Example error

User writes:

```elixir
field :name, :string, derive: "sanitize(trimm) validate(string)"
                                          ^^^^^ typo
```

Today: compiles, fails on first `builder/2` call with a vague "Unexpected type error in name field".

After: `mix compile` fails with:

```
** (Spark.Error.DslError) my_app/lib/my_app/user.ex:14:7:
   guardedstruct -> field :name -> derive
   invalid derive on field :name: unknown sanitize op `:trimm`
     string was: "sanitize(trimm) validate(string)"
```

That's the line your earlier message asks for ("not good in compile time"). This is the fix.

---

## 11. Module generation strategy

The current library generates one real `defmodule` per `sub_field`. The rewrite preserves this — submodules are user-callable, have their own `builder/2`, etc. The mechanics change.

### 11.1. Top-level user module

The user writes:

```elixir
defmodule MyApp.User do
  use GuardedStruct
  guardedstruct enforce: true do … end
end
```

`GuardedStruct.Transformers.GenerateBuilder` injects, via `Spark.Dsl.Transformer.eval/3`, the following quoted block into `MyApp.User`:

```elixir
quote do
  defstruct unquote(struct_fields_with_defaults)
  @enforce_keys unquote(enforce_keys)

  if unquote(opaque) do
    @opaque t() :: %__MODULE__{unquote_splicing(types)}
  else
    @type t() :: %__MODULE__{unquote_splicing(types)}
  end

  def keys, do: unquote(keys)
  def keys(:all), do: GuardedStruct.Runtime.all_keys(__MODULE__)
  def keys(field) when is_atom(field), do: field in unquote(keys)

  def enforce_keys, do: unquote(enforce_keys)
  def enforce_keys(:all), do: GuardedStruct.Runtime.all_enforce_keys(__MODULE__)
  def enforce_keys(field) when is_atom(field), do: field in unquote(enforce_keys)

  def __information__, do: unquote(Macro.escape(info_struct))

  def builder(attrs, error \\ false), do: GuardedStruct.Runtime.build(__MODULE__, attrs, error)
  def builder({key, attrs}, error) when is_tuple({key, attrs}),
    do: GuardedStruct.Runtime.build(__MODULE__, {key, attrs}, error)
  def builder({key, attrs, type}, error),
    do: GuardedStruct.Runtime.build(__MODULE__, {key, attrs, type}, error)
end
```

The `eval/3` runs after all transformers, before the verifiers, in the user module's context. No surprises.

### 11.2. Sub_field submodules

For each `%SubField{}` in DSL state, `GuardedStruct.Transformers.GenerateSubFieldModules` calls `Spark.Dsl.Transformer.async_compile/2`:

```elixir
def transform(dsl_state) do
  parent = Transformer.get_persisted(dsl_state, :module)

  walk_sub_fields(dsl_state, [:guardedstruct], [parent])
  |> Enum.reduce({:ok, dsl_state}, fn {path, sub_field, ctx}, {:ok, acc} ->
    submodule = Module.concat(path)
    body = build_submodule_body(sub_field, ctx)

    {:ok,
     Transformer.async_compile(acc, fn ->
       Module.create(submodule, body, file: ctx.file, line: ctx.line)
     end)}
  end)
end

defp build_submodule_body(sub_field, ctx) do
  quote do
    defstruct unquote(...)
    @enforce_keys unquote(...)
    @type t() :: %__MODULE__{...}

    def keys, do: unquote(...)
    def enforce_keys, do: unquote(...)
    def __information__, do: unquote(...)
    def builder(attrs, error \\ false),
      do: GuardedStruct.Runtime.build(__MODULE__, attrs, error)
    def builder({key, attrs}, error), do: ...
    def builder({key, attrs, type}, error), do: ...

    if unquote(sub_field.error?) do
      defmodule Error do
        defexception [:errors, :term]
        @impl true
        def message(%{errors: errs}), do: "build errors: #{inspect(errs)}"
      end
    end
  end
end
```

Two important details:

- `async_compile` lets all submodules compile in parallel — the current library serializes them via `defmodule` inside `quote` inside `defmacro`, which is significantly slower for deep trees.
- Source location is preserved via `file:` and `line:` from the entity's `__spark_metadata__.anno`. Stack traces from a failing submodule point at the user's `sub_field` call, not at our transformer.

### 11.3. Conditional_field synthetic submodules

`conditional_field` children that are `sub_field`s currently get auto-numbered names: `Address1`, `Address2`, `Address3` (see `lib/guarded_struct.ex:2241-2249`). This naming continues — the `NormalizeConditional` transformer assigns the numbers, and `GenerateSubFieldModules` materializes them.

### 11.4. Error modules

`error: true` (top-level or per-sub_field) generates `<Mod>.Error` via `defexception`. Currently done via `defmacro create_error_module/0`. New approach: a tiny `Module.create` invocation inside `GenerateSubFieldModules` (or a dedicated `GenerateErrorModules` transformer for clarity).

---

## 12. Runtime `builder/2` pipeline

The runtime is the simplest part — most of `lib/guarded_struct.ex:1582-2007` ports almost verbatim into `GuardedStruct.Runtime`, with these structural improvements:

1. **No more `Module.get_attribute(module, &1)` lookups** (line 1328). The `info_struct` is captured at compile time inside `__information__/0`. Runtime reads from there or from the Spark Info module.
2. **`derive` ops are pre-parsed.** `Derive.derive/1` becomes `GuardedStruct.Derive.run/2`, fed pre-parsed op-lists from the entity.
3. **Core key paths are pre-split.** `from_core_key/1`, `on_core_key/2` get `[:root, :name]` instead of `"root::name"`.
4. **Each step is a private function with a single signature.** No more `{:ok, attrs}`/`{:error, _, :halt}` dual returns. Use `with`:

   ```elixir
   def build(module, attrs, error?) do
     with {:ok, normalized} <- normalize_input(attrs),
          {:ok, attrs} <- authorized_fields(normalized, info(module)),
          {:ok, attrs} <- required_fields(attrs, info(module)),
          {:ok, attrs} <- auto_core_key(attrs, info(module)),
          {:ok, attrs} <- domain_core_key(attrs, info(module)),
          {:ok, attrs} <- on_core_key(attrs, info(module)),
          {:ok, attrs} <- from_core_key(attrs, info(module)),
          {:ok, attrs} <- conditional_fields(attrs, info(module)),
          {:ok, attrs, sub_data, sub_errors} <- sub_fields(attrs, info(module)),
          {:ok, attrs, validated_errors} <- fields(attrs, info(module)),
          {:ok, output} <- main_validator(attrs, info(module)),
          {:ok, output} <- replace_condition_field_derives(output, ...),
          {:ok, output} <- derive(output, info(module)) do
       finalize(output, sub_data, sub_errors, validated_errors)
     else
       {:error, errs} when error? -> raise(Module.safe_concat(module, Error), errors: errs)
       error -> error
     end
   end
   ```

The pipeline order is preserved bit-for-bit so existing tests pass unchanged.

### 12.1. Recursive descent into nested structures

`sub_fields/2` calls `submodule.builder/2` recursively. `conditional_fields/2` matches each child; if a child is a `sub_field` it dispatches to that submodule's builder; if a child is itself a `conditional_field` (the new case), it recurses. The `Runtime` module is ~400-500 LOC, mostly mechanical translation of today's logic.

---

## 13. Error paths and `DslError`

Every transformer / verifier / runtime check produces structured errors. The two paths:

### 13.1. Compile-time errors

Use `Spark.Error.DslError`:

```elixir
raise Spark.Error.DslError,
  message: "validator #{inspect(mod)}.#{fun}/2 not exported for field #{f.name}",
  path: [:guardedstruct, :field, f.name, :validator],
  module: Spark.Dsl.Verifier.get_persisted(dsl_state, :module)
```

When raised, Elixir prints:

```
** (Spark.Error.DslError) lib/my_app/user.ex:42:14:
   guardedstruct -> field :name -> validator
   validator MyApp.NoMod.foo/2 not exported for field :name
```

Source location comes from the entity's `__spark_metadata__.anno`, captured automatically at DSL parse time. The `path:` shows the DSL nesting.

### 13.2. Runtime errors

Unchanged. The current `{:error, errors}` shape, `defexception <Mod>.Error`, and the configurable `Messages` backend all keep working as-is. The rewrite only moves *compile-time* errors out of macro internals; the runtime error format is API.

---

## 14. Migration / delivery plan in phases

The library is too big to swap atomically. Here's how to land it without a flag day.

### Phase 0 — design doc + skeleton (1 day)

- This document.
- New branch `spark-rewrite`.
- `mix.exs` adds `{:spark, "~> 2.7"}`.
- Empty `lib/guarded_struct/dsl.ex` (the extension), `lib/guarded_struct/dsl/{field,sub_field,conditional_field}.ex` (the structs), `lib/guarded_struct/transformers/`, `lib/guarded_struct/verifiers/`, `lib/guarded_struct/runtime.ex`.
- `.formatter.exs` adds `import_deps: [:spark]`, `plugins: [Spark.Formatter]`.

### Phase 1 — basic struct generation (2-3 days)

- `field` entity with `name`, `type`, `enforce`, `default`.
- `GenerateBuilder` transformer producing `defstruct`, `@type t()`, `@enforce_keys`, `keys/0`, `enforce_keys/0`.
- A no-op `builder/2` that just builds the struct and runs `required_fields`.
- Make `test/basic_types_test.exs` pass.

### Phase 2 — derive engine, compile-time parsing (2-3 days)

- `GuardedStruct.Derive.Compile.parse/1` (moved from `Parser.parser/1`).
- `ParseDerive` transformer.
- `VerifyDeriveSyntax` verifier.
- `GuardedStruct.Derive.run/2` runtime.
- Re-port all sanitizers from `sanitizer_derive.ex` and validators from `validation_derive.ex` into `GuardedStruct.Derive.Sanitize` / `Validate` modules.
- Make `test/derive_test.exs` pass (846 LOC).

### Phase 3 — validator + main_validator (1 day)

- `validator: {Mod, :fn}` per-field.
- `main_validator: {Mod, :fn}` per-section.
- Caller-module fallback for both.
- `VerifyValidatorMFA` verifier.
- Make `test/validator_derive_test.exs` pass (544 LOC).

### Phase 4 — sub_field (recursive, real submodules) (3-4 days)

- `sub_field` entity with `recursive_as: :sub_fields`.
- `GenerateSubFieldModules` transformer.
- Runtime recursion in `sub_fields_validating`.
- `error: true` per-submodule via `GenerateErrorModules`.
- `struct:` / `structs:` external module references.
- Make `test/global_test.exs` pass (570 LOC).

### Phase 5 — core keys (auto, on, from, domain) (3-4 days)

- `ParseCoreKeys` and `ParseDomainExpr` transformers.
- `VerifyAutoMFA`, `VerifyFromPath`, `VerifyOnPath`, `VerifyDomainExpressions` verifiers.
- Runtime application steps.
- Make `test/core_keys_test.exs` pass (1,035 LOC).

### Phase 6 — conditional_field (4-5 days, the hard one)

- `conditional_field` entity with `recursive_as: :conditional_fields`.
- `VerifyConditionalChildrenShareName` verifier.
- Runtime conditional resolution with priority, hint, list, list-of-list.
- Auto-numbered submodule names (`Address1`, `Address2`).
- Make `test/conditional_field_test.exs` pass (2,541 LOC).
- **Enable `test/nested_conditional_field_test.exs`** — un-comment, write new tests, ensure nested conditionals work.

### Phase 7 — i18n message backend, exceptions handler (0.5 day)

- Port `lib/messages.ex` verbatim (no Spark interaction needed).
- Wire into `GuardedStruct.Runtime`.
- All errors go through `translated_message/1,2`.

### Phase 8 — new features unlocked by the rewrite (timeline TBD)

- #5 virtual fields.
- #11 dynamic key support.
- #2 single-validation API.
- #3 `mix guarded_struct.gen.schema`.
- #6 record support inside `guardedstruct`.
- #4 more predefined validators / sanitizers.

### Phase 9 — release (0.5 day)

- `CHANGELOG.md` entry: `v0.1.0` (semver bump because internals changed; public API didn't).
- README update: "now powered by Spark".
- Hex publish.

Total: **~3 weeks** of focused work. Phases 1-7 are the rewrite proper (2 weeks). Phase 8 is incremental and can ship as 0.1.x point releases.

---

## 15. Test strategy

The 6,300 LOC of existing tests are the spec. Rule: **don't change them**. If a test fails, the rewrite is wrong. Three exceptions:

1. **`test/nested_conditional_field_test.exs`** is currently a placeholder — every test is commented out citing #25. Un-comment them (they describe the expected behaviour) and add ~10 new tests for nested-conditional edge cases.
2. **`test/nested_sub_field_test.exs`** is a placeholder citing #12. Un-comment, expand.
3. **Tests that assert the macro raises** (e.g. assert_raise with `unsupported_conditional_field`) get *deleted*. The behaviour they assert is the bug we're fixing.

### 15.1. CI per phase

Update `.github/workflows/ci.yml` to gate per phase:

```yaml
- name: Run phase tests
  run: mix test --only phase:${{ matrix.phase }}
```

Mark each test file with `@moduletag phase: N` so we can run only the green tests during the rewrite. By Phase 6, all tests run.

### 15.2. New compile-time tests

Add `test/compile_time_test.exs` for things only the new architecture can verify:

- `assert_raise Spark.Error.DslError, fn -> defmodule Bad do … field :name, :string, derive: "sanitize(trimm)" end end`
- Same for unknown validator MFA, bad `from:` path, unknown `domain:` type, etc.

These tests prove the user-facing improvement: typos surface at compile time.

### 15.3. Property tests (optional but recommended)

Use `stream_data` to property-test the derive engine: for each known sanitize/validate op, assert `parse(to_string(op))` round-trips. This catches drift between docs and implementation.

---

## 16. What Spark cannot do

Honest list of limits, with workarounds.

### 16.1. The "real `defmodule` per sub_field" idiom is unusual

Spark's idiom is "one module + nested struct + Info introspection" (Ash embedded resources expect users to write a separate `defmodule MyApp.Profile do use Ash.Resource, data_layer: :embedded end`). We swim against the current by using `Module.create` from a transformer. This works (Spark's own internals do it), but:

- Async compile means we can't read submodule state during a transformer pass on the parent. Workaround: keep all state in the parent's DSL state until everything is generated, then materialize.
- Stack traces involve our transformer in addition to the user's source. Workaround: pass `file:` and `line:` from the entity's `anno` to `Module.create`.

### 16.2. Configurable runtime backends untouched

`config :guarded_struct, message_backend: …` is a runtime concern Spark doesn't help with. Keep it as today (read in the runtime body of `builder/2`).

### 16.3. Per-DSL-invocation state

There's no first-class "fresh accumulator per `guardedstruct` block" hook. Doesn't matter for us because `guardedstruct` is the top-level section and each user module has exactly one.

### 16.4. Two-syntax tax

Spark supports both `field :name, :type, opts` (keyword form) and `field :name, :type do … end` (block form). Our DSL uses keyword form for `field`. No problem, just be consistent.

### 16.5. Dynamic syntax based on option values

If we ever wanted "if `dynamic: true` is set, allow new keywords inside the block", that's a wall. Workaround: separate entities (`field` vs `dynamic_field`) with disjoint schemas.

### 16.6. `Module.create` adds compile dependencies

Generating a submodule via `Module.create` from inside a transformer means the parent module compile-depends on the child. For deep trees this can pessimize incremental builds. Workaround: `async_compile` parallelizes within one parent's compile; cross-parent the deps are unavoidable but no worse than today.

### 16.7. Some macro hygiene tricks aren't available

The current library does `Module.eval_quoted(__CALLER__.module, ast)` inside `register_struct/4`. Spark transformers can't grab `__CALLER__`. They can read `Macro.Env.location/1` from the entity's anno. For our needs this is sufficient.

---

## 17. Open questions

These need a decision before Phase 1 starts.

1. **Drop or keep `module: SubName` on `guardedstruct`?** Currently `guardedstruct module: Foo do … end` wraps the whole block in `defmodule Foo`. Useful but rare. Option A: keep, generate via a `Module.create` in a top-level wrapper. Option B: deprecate, force users to write `defmodule Foo do use GuardedStruct ... end`. **Recommendation: keep, for backward compat.**
2. **`use GuardedStruct` vs `use GuardedStruct.Resource`?** Spark idiom is per-resource type. We have one. **Recommendation: keep `use GuardedStruct`** — invisible change.
3. **Where should the Info module live?** `GuardedStruct.Info`. Standard.
4. **Spark version pinning.** `~> 2.7` is fine; if Spark 3.0 ships during the rewrite, re-evaluate.
5. **Hex package name.** Stay `:guarded_struct`. Major bump to `0.1.0` (or `1.0.0` if the API really doesn't change — depends on how strict semver is here).
6. **Should we expose the Spark extension publicly?** I.e. let third parties patch our DSL with their own validators. Spark supports it. **Recommendation: yes, deferred to v0.2** — easy to add later, no commitment now.
7. **Drop optional deps (`html_sanitize_ex`, `email_checker`, `ex_url`, `ex_phone_number`)?** They cause compile-time conditional code. Keep for v0.1; revisit later.

---

## Appendix A — the new module layout

```
lib/
├── guarded_struct.ex                              # use Spark.Dsl, the public macro entrypoint
├── guarded_struct/
│   ├── dsl.ex                                     # the Spark.Dsl.Extension
│   ├── dsl/
│   │   ├── field.ex                               # %Field{}
│   │   ├── sub_field.ex                           # %SubField{}
│   │   └── conditional_field.ex                   # %ConditionalField{}
│   ├── info.ex                                    # use Spark.InfoGenerator
│   ├── transformers/
│   │   ├── parse_derive.ex
│   │   ├── parse_core_keys.ex
│   │   ├── parse_domain_expr.ex
│   │   ├── normalize_conditional.ex
│   │   ├── generate_builder.ex
│   │   ├── generate_sub_field_modules.ex
│   │   └── generate_error_modules.ex
│   ├── verifiers/
│   │   ├── verify_conditional_children_share_name.ex
│   │   ├── verify_validator_mfa.ex
│   │   ├── verify_auto_mfa.ex
│   │   ├── verify_from_path.ex
│   │   ├── verify_on_path.ex
│   │   ├── verify_domain_expressions.ex
│   │   └── verify_derive_syntax.ex
│   ├── runtime.ex                                 # the build/3 pipeline
│   ├── runtime/
│   │   ├── pipeline.ex                            # the with-chain
│   │   ├── auto.ex
│   │   ├── domain.ex
│   │   ├── on.ex
│   │   ├── from.ex
│   │   ├── conditional.ex
│   │   ├── sub_field.ex
│   │   ├── field.ex
│   │   └── main_validator.ex
│   ├── derive/
│   │   ├── compile.ex                             # parse strings → ops
│   │   ├── run.ex                                 # apply ops at runtime
│   │   ├── sanitize.ex                            # all sanitizer functions
│   │   └── validate.ex                            # all validator functions
│   └── messages.ex                                # unchanged from today
└── …
```

About 15 small files instead of one 2,910-LOC monolith.

---

## Appendix B — quick `mix.exs` change

```elixir
defp deps do
  [
    # NEW
    {:spark, "~> 2.7"},

    # KEEP
    {:html_sanitize_ex, "~> 1.5"},
    {:ex_doc, "~> 0.40.1", only: :dev, runtime: false},
    {:email_checker, "~> 0.2.4", optional: true, only: :test},
    {:ex_url, "~> 2.0.2", optional: true, only: :test},
    {:ex_phone_number, "~> 0.4.11", optional: true, only: :test},
    {:sweet_xml, github: "kbrw/sweet_xml", branch: "master", override: true,
     optional: true, only: :test}
  ]
end
```

`.formatter.exs`:

```elixir
[
  import_deps: [:spark],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  plugins: [Spark.Formatter]
]
```

CI (`.github/workflows/ci.yml`) — add:

```yaml
- name: Spark formatter check
  run: mix spark.formatter --check --extensions GuardedStruct.Dsl
- name: Spark cheat-sheets check
  run: mix spark.cheat_sheets --check --extensions GuardedStruct.Dsl
```

---

## Appendix C — references

### Current source (the inputs)

- `lib/guarded_struct.ex` — 2,910 LOC, the macro core
- `lib/messages.ex` — 420 LOC, i18n backend
- `lib/derive/derive.ex` — 198 LOC, the derive runtime
- `lib/derive/parser.ex` — 264 LOC, the string DSL parser (incl. the `unsupported_conditional_field` raise sites)
- `lib/derive/sanitizer_derive.ex` — 116 LOC, all sanitizers
- `lib/derive/validation_derive.ex` — 704 LOC, all validators
- `lib/helper/extra.ex` — 107 LOC, util
- `test/conditional_field_test.exs` — 2,541 LOC, conditional spec
- `test/core_keys_test.exs` — 1,035 LOC, core key spec
- `test/derive_test.exs` — 846 LOC, derive spec
- `test/global_test.exs` — 570 LOC, end-to-end spec
- `test/validator_derive_test.exs` — 544 LOC, validator+main_validator spec
- `test/basic_types_test.exs` — 205 LOC, struct generation spec
- `test/nested_conditional_field_test.exs` — placeholder, to be filled
- `test/nested_sub_field_test.exs` — placeholder, to be filled

### Spark documentation

- Hexdocs: https://hexdocs.pm/spark
- `Spark.Dsl.Entity` — entity definition reference
- `Spark.Dsl.Section` — section definition reference
- `Spark.Dsl.Transformer` — `eval/3`, `async_compile/2`, `add_entity/3`, `replace_entity/4`, `persist/3`, `get_persisted/3`, `get_entities/2`, `get_option/3`
- `Spark.Dsl.Verifier` — verify callback contract
- `Spark.InfoGenerator` — generated accessors
- `Spark.Error.DslError` — `path:`, `module:`, anno-aware error
- `Spark.Formatter` — formatter plugin

### Reference Spark codebases to crib from

- **Ash.Resource.Dsl** — `lib/ash/resource/dsl.ex` lines 36-232. Multiple entities sharing one target struct. The model for our `field` family.
- **Ash.Policy.Authorizer** — `lib/ash/policy/authorizer/authorizer.ex` lines 200-260. `policy_group` with `recursive_as: :policies`. **Read this first** — it's the canonical recursive-entity example and matches our `sub_field` shape almost exactly.
- **Spark "get started" tutorial** — `documentation/tutorials/get-started-with-spark.md`. ~200 LOC end-to-end example with a section, an entity, a transformer (`AddId`), an `eval/3`-based generator (`GenerateValidate`), and a verifier (`VerifyRequired`). Closest existing example to ours; copy as a skeleton.

### Issues this rewrite addresses

- #1 — VS Code autocomplete (free with Spark)
- #2 — single validation API (post-rewrite, easy)
- #3 — mix schema generator (post-rewrite, easy)
- #4 — more predefined validators (incremental, no rewrite needed)
- #5 — virtual fields (post-rewrite, easy)
- #6 — record support (post-rewrite, easy)
- #7, #8, #25 — nested conditional_field (this rewrite, one line of `recursive_as`)
- #11 — dynamic keys (post-rewrite, easy)
- #12 — nested list validation (this rewrite, free with recursive entities)

---

## Appendix D — every derive key, with a simple example

This appendix enumerates every sanitizer and validator the current library ships, plus a sketch of the **new Spark-native syntax** that replaces today's string-based derive.

### How the syntax changes (proposal)

Today, derive is a single string parsed at runtime:

```elixir
derive: "sanitize(trim, upcase) validate(string, max_len=20, min_len=3, enum=Atom[admin::user::banned])"
```

Under Spark we keep the string form for backward compatibility, but also accept a native-Elixir form (parsed by Spark's schema, not by us). Three accepted shapes:

```elixir
# Shape 1 — legacy string, parsed at compile time by ParseDerive transformer
derive: "sanitize(trim, upcase) validate(string, max_len=20)"

# Shape 2 — flat keyword/atom list (the form your message hints at)
derive: [:trim, :upcase, :string, max_len: 20, min_len: 3]

# Shape 3 — split sanitize/validate (most explicit, recommended for new code)
sanitize: [:trim, :upcase],
validate: [:string, max_len: 20, min_len: 3, enum: {:atom, [:admin, :user, :banned]}]
```

For the enum/regex/equal/either/custom families that take parameters, the native form uses tuples:

| Legacy string | Native Spark form |
| --- | --- |
| `"validate(enum=String[admin::user])"` | `enum: {:string, ["admin", "user"]}` |
| `"validate(enum=Atom[x::y::t])"` | `enum: {:atom, [:x, :y, :t]}` |
| `"validate(enum=Integer[1::2::3])"` | `enum: {:integer, [1, 2, 3]}` |
| `"validate(equal=Atom::name)"` | `equal: {:atom, :name}` |
| `"validate(regex='^[a-z]+$')"` | `regex: ~r/^[a-z]+$/` |
| `"validate(either=[string, enum=Integer[1::2]])"` | `either: [:string, {:enum, {:integer, [1, 2]}}]` |
| `"validate(custom=[Mod, fn?])"` | `custom: {Mod, :fn?}` |
| `"validate(max_len=20)"` | `max_len: 20` |
| `"validate(tell=98)"` | `tell: 98` |
| `"sanitize(tag=strip_tags)"` | `tag: :strip_tags` |

The `ParseDerive` transformer normalizes all three shapes into the same internal op-list, so the runtime cares about exactly one form. Bad input from any of the three shapes raises `Spark.Error.DslError` at compile time with file:line:column.

---

### Sanitizers

#### `trim`

Trim whitespace from both ends of a string.

```elixir
field :name, :string, derive: "sanitize(trim)"
# "  Mishka  " → "Mishka"
```

#### `upcase`

```elixir
field :code, :string, derive: "sanitize(upcase)"
# "abc" → "ABC"
```

#### `downcase`

```elixir
field :slug, :string, derive: "sanitize(downcase)"
# "FooBar" → "foobar"
```

#### `capitalize`

```elixir
field :title, :string, derive: "sanitize(capitalize)"
# "mishka group" → "Mishka group"
```

#### `basic_html` *(requires `:html_sanitize_ex`)*

Whitelist a small basic-HTML subset.

```elixir
field :bio, :string, derive: "sanitize(basic_html)"
# "<script>x</script><p>hi</p>" → "<p>hi</p>"
```

#### `html5` *(requires `:html_sanitize_ex`)*

```elixir
field :body, :string, derive: "sanitize(html5)"
# "<section>hi</section>" → "<section>hi</section>"
```

#### `markdown_html` *(requires `:html_sanitize_ex`)*

```elixir
field :readme, :string, derive: "sanitize(markdown_html)"
# "[link](https://x)" → "[link](https://x)"
```

#### `strip_tags` *(requires `:html_sanitize_ex`)*

```elixir
field :name, :string, derive: "sanitize(strip_tags)"
# "<p>Mishka</p>" → "Mishka"
```

#### `tag=<sub-sanitizer>` *(requires `:html_sanitize_ex`)*

Trim, then apply a named html_sanitize_ex op, then trim again.

```elixir
field :title, :string, derive: "sanitize(tag=strip_tags)"
# "  <p>hi</p>  " → "hi"
```

#### `string_float`

Strip tags then `Float.parse/1`. Falls back to `0.0`.

```elixir
field :amount, :float, derive: "sanitize(string_float)"
# "<p>3.5</p>" → 3.5
```

#### `string_integer`

Strip tags then `Integer.parse/1`. Falls back to `0`.

```elixir
field :age, :integer, derive: "sanitize(string_integer)"
# "<p>42</p>" → 42
```

---

### Built-in type validators

#### `string`

```elixir
field :name, :string, derive: "validate(string)"
```

#### `integer`

```elixir
field :age, :integer, derive: "validate(integer)"
```

#### `list`

```elixir
field :tags, {:array, :string}, derive: "validate(list)"
```

#### `atom`

```elixir
field :role, :atom, derive: "validate(atom)"
```

#### `bitstring`

```elixir
field :raw, :bitstring, derive: "validate(bitstring)"
```

#### `boolean`

```elixir
field :active, :boolean, derive: "validate(boolean)"
```

#### `exception`

```elixir
field :err, :any, derive: "validate(exception)"
```

#### `float`

```elixir
field :price, :float, derive: "validate(float)"
```

#### `function`

```elixir
field :callback, :any, derive: "validate(function)"
```

#### `map`

```elixir
field :meta, :map, derive: "validate(map)"
```

#### `nil_value`

Asserts the value is `nil`.

```elixir
field :placeholder, :any, derive: "validate(nil_value)"
```

#### `not_nil_value`

Asserts the value is not `nil`.

```elixir
field :id, :any, derive: "validate(not_nil_value)"
```

#### `number`

Integer or float.

```elixir
field :score, :any, derive: "validate(number)"
```

#### `pid`

```elixir
field :worker, :any, derive: "validate(pid)"
```

#### `port`

```elixir
field :handle, :any, derive: "validate(port)"
```

#### `reference`

```elixir
field :ref, :any, derive: "validate(reference)"
```

#### `struct`

Any struct (`is_struct/1`).

```elixir
field :user, :any, derive: "validate(struct)"
```

#### `tuple`

```elixir
field :pair, :any, derive: "validate(tuple)"
```

---

### Emptiness / size validators

#### `not_empty`

Works on binary, list, or map.

```elixir
field :tags, {:array, :string}, derive: "validate(not_empty)"
```

#### `not_empty_string`

Stricter: must be `is_binary/1` and not `""`.

```elixir
field :name, :string, derive: "validate(not_empty_string)"
```

#### `not_flatten_empty`

For nested lists: `List.flatten/1` must not be `[]`.

```elixir
field :rows, {:array, :any}, derive: "validate(not_flatten_empty)"
# [[]] → error;  [[1]] → ok
```

#### `not_flatten_empty_item`

Like above, but additionally rejects any single empty inner list.

```elixir
field :rows, {:array, :any}, derive: "validate(not_flatten_empty_item)"
# [[1], []] → error;  [[1], [2]] → ok
```

#### `max_len=N`

For binary length, integer value, range, or list length.

```elixir
field :name, :string, derive: "validate(max_len=20)"
field :age,  :integer, derive: "validate(max_len=110)"
```

#### `min_len=N`

```elixir
field :name, :string, derive: "validate(min_len=3)"
field :age,  :integer, derive: "validate(min_len=18)"
```

#### `range`

Asserts the value is a `Range`.

```elixir
field :window, :any, derive: "validate(range)"
# 1..10 → ok
```

#### `queue`

Asserts the value is an Erlang `:queue`.

```elixir
field :pending, :any, derive: "validate(queue)"
```

---

### Format validators

#### `url`

Must have scheme + host + resolvable hostname (calls `:inet.gethostbyname`).

```elixir
field :site, :string, derive: "validate(url)"
# "https://github.com" → ok
```

#### `geo_url` *(requires `:ex_url`)*

```elixir
field :location, :string, derive: "validate(geo_url)"
# "48.198634,-16.371648,3.4;crs=wgs84" → "geo:48.198634,…"
```

#### `location` *(requires `:ex_url`)*

Like `geo_url` but with whitespace tolerance.

```elixir
field :location, :string, derive: "validate(location)"
# "48.198634, -16.371648" → "geo:48.198634,-16.371648"
```

#### `tell` *(requires `:ex_url`)*

Phone-number format check.

```elixir
field :mobile, :string, derive: "validate(tell)"
# "09368090000" → ok
```

#### `tell=<country_code>` *(requires `:ex_url` + `:ex_phone_number`)*

```elixir
field :mobile, :string, derive: "validate(tell=98)"
# "+989368090000" → ok
```

#### `email` *(requires `:email_checker`)*

MX-record-aware email check.

```elixir
field :email, :string, derive: "validate(email)"
```

#### `email_r`

Regex-only email check (no MX lookup, no extra deps).

```elixir
field :email, :string, derive: "validate(email_r)"
```

#### `string_boolean`

Must be the string `"true"` or `"false"`.

```elixir
field :active, :string, derive: "validate(string_boolean)"
```

#### `datetime`

`DateTime.from_iso8601/1` must succeed.

```elixir
field :inserted_at, :string, derive: "validate(datetime)"
# "2023-08-04T13:46:53Z" → ok
```

#### `date`

`Date.from_iso8601/1` must succeed.

```elixir
field :birthday, :string, derive: "validate(date)"
# "2000-01-15" → ok
```

#### `regex='<pattern>'`

```elixir
field :slug, :string, derive: ~S|validate(regex='^[a-z][a-z0-9_-]+$')|
```

#### `ipv4`

Four `0..255` octets.

```elixir
field :ip, :string, derive: "validate(ipv4)"
# "192.168.0.1" → ok
```

#### `uuid`

Standard UUID v1-v5 hex format.

```elixir
field :id, :string, derive: "validate(uuid)"
# "d528ba1e-cd85-4f61-954c-7c8aa8e8decc" → ok
```

#### `username`

Library-specific: 5-34 chars, must start with a letter, only `[a-zA-Z0-9_]`.

```elixir
field :handle, :string, derive: "validate(username)"
```

#### `full_name`

Library-specific: only lowercase letters and spaces, must not start with a space.

```elixir
field :family, :string, derive: "validate(full_name)"
```

---

### String-as-number validators

#### `string_float`

Strict — `String.to_float/1` must fully consume the string.

```elixir
field :amount, :string, derive: "validate(string_float)"
# "3.5" → ok;  "3.5x" → error
```

#### `some_string_float`

Lenient — `Float.parse/1` must succeed (trailing junk allowed).

```elixir
field :amount, :string, derive: "validate(some_string_float)"
# "3.5sss" → ok
```

#### `string_integer`

Strict — `String.to_integer/1` must fully consume.

```elixir
field :age, :string, derive: "validate(string_integer)"
# "42" → ok;  "42x" → error
```

#### `some_string_integer`

Lenient — `Integer.parse/1` must succeed.

```elixir
field :age, :string, derive: "validate(some_string_integer)"
# "42x" → ok
```

---

### Set / equality validators

#### `enum=String[a::b::c]`

```elixir
field :role, :string, derive: "validate(enum=String[admin::user::banned])"
# Spark form: enum: {:string, ["admin", "user", "banned"]}
```

#### `enum=Atom[a::b::c]`

```elixir
field :role, :atom, derive: "validate(enum=Atom[admin::user::banned])"
# Spark form: enum: {:atom, [:admin, :user, :banned]}
```

#### `enum=Integer[1::2::3]`

```elixir
field :level, :integer, derive: "validate(enum=Integer[1::2::3])"
```

#### `enum=Float[1.5::2.0::4.5]`

```elixir
field :grade, :float, derive: "validate(enum=Float[1.5::2.0::4.5])"
```

#### `enum=Map[%{...}::%{...}]`

```elixir
field :status, :map,
  derive: "validate(enum=Map[%{status: 1}::%{status: 2}::%{status: 3}])"
```

#### `enum=Tuple[{...}::{...}]`

```elixir
field :pair, :any,
  derive: "validate(enum=Tuple[{:admin, 1}::{:user, 2}::{:banned, 3}])"
```

#### `equal=<Type>::<value>`

Strict equality against a typed literal.

```elixir
field :name,  :string,  derive: "validate(equal=String::Mishka)"
field :role,  :atom,    derive: "validate(equal=Atom::admin)"
field :level, :integer, derive: "validate(equal=Integer::1)"
field :rate,  :float,   derive: "validate(equal=Float::1.5)"
field :meta,  :map,     derive: ~S|validate(equal=Map::%{name: "mishka"})|
```

#### `either=[v1, v2, …]`

Pass if **any** sub-validator passes.

```elixir
field :score, :any, derive: "validate(either=[integer, max_len=4])"
field :id,    :any, derive: "validate(either=[string, enum=Integer[1::2::3]])"
```

#### `custom=[Module, function?]`

Call user code; must return `true`.

```elixir
defmodule Check do
  def is_stuff?("ok"), do: true
  def is_stuff?(_),    do: false
end

field :status, :string, derive: "validate(custom=[Check, is_stuff?])"
```

---

### Pluggable derives (config-registered)

The library lets you register your own sanitize / validate names via `:guarded_struct, :validate_derive` and `:guarded_struct, :sanitize_derive` config:

```elixir
defmodule MyValidate do
  def validate(:my_check, input, field) do
    if is_binary(input), do: input,
      else: {:error, field, :my_check, "must be string"}
  end
end

config :guarded_struct, validate_derive: MyValidate

field :name, :string, derive: "validate(my_check)"
```

Same shape for sanitizers (`def sanitize(:my_op, input)`). Both options accept a single module or a list of modules; the rewrite preserves this verbatim.

---

## Appendix E — every non-derive option, with a simple example

This is the companion to Appendix D. Where Appendix D enumerated every sanitize/validate rule that goes inside the `derive:` string, this appendix enumerates everything else: top-level options on `guardedstruct`, per-field options on `field` / `sub_field` / `conditional_field`, the four **core keys** (`auto`, `on`, `from`, `domain`), and the special calling shapes of `builder/2`. Same one-line-example format.

I went through `lib/guarded_struct.ex` and grepped every `opts[:…]` and `Keyword.get(opts, :…)` site to make sure nothing is missing. If a key exists in the source, it has a heading below.

### 1. Top-level options on `guardedstruct do … end`

#### `enforce: true`

Make every field of this block enforced unless it has a `default:` or its own `enforce: false`.

```elixir
guardedstruct enforce: true do
  field :name, :string                    # enforced
  field :nick, :string, enforce: false    # not enforced
  field :tier, :integer, default: 1       # not enforced (has default)
end
```

#### `opaque: true`

Generate `@opaque t()` instead of `@type t()` so callers can't pattern-match the internals.

```elixir
guardedstruct opaque: true do
  field :id, :string
end
```

#### `module: SubName`

Wrap the whole struct in a sub-module without writing `defmodule` yourself.

```elixir
defmodule TestModule do
  use GuardedStruct
  guardedstruct module: Struct do
    field :field, :any
  end
end
# Creates TestModule.Struct.builder/2 etc.
```

#### `error: true`

Generate a `<Module>.Error` exception so callers can use `builder(attrs, true)` to raise instead of get `{:error, …}`.

```elixir
guardedstruct error: true do
  field :name, :string
end

MyMod.builder(%{name: 1}, true)
# raises %MyMod.Error{errors: […]}
```

#### `authorized_fields: true`

Reject unknown keys instead of silently dropping them.

```elixir
guardedstruct authorized_fields: true do
  field :name, :string
end

MyMod.builder(%{name: "x", evil: "y"})
# {:error, %{action: :authorized_fields, fields: [:evil], …}}
```

#### `main_validator: {Mod, :fn}`

Whole-output validator that runs after every per-field validator. Receives the full attrs map, returns `{:ok, attrs} | {:error, errors}`.

```elixir
guardedstruct main_validator: {MyApp.UserChecks, :main} do
  field :name, :string
  field :role, :string
end

# MyApp.UserChecks.main(attrs) -> {:ok, attrs} | {:error, [%{...}]}
```

> If the option is omitted but the surrounding module defines `def main_validator/1`, that one is used automatically.

#### `validate_derive: Mod` / `validate_derive: [Mod1, Mod2]`

Register custom validate-derive name(s). Combine with the runtime `:guarded_struct` Application env.

```elixir
guardedstruct validate_derive: MyApp.CustomValidates do
  field :id, :integer, derive: "validate(my_check)"
end
```

#### `sanitize_derive: Mod` / `sanitize_derive: [Mod1, Mod2]`

Same idea for sanitize.

```elixir
guardedstruct sanitize_derive: [MyApp.SanA, MyApp.SanB] do
  field :name, :string, derive: "sanitize(my_op) validate(string)"
end
```

---

### 2. Per-field options (apply to `field`, `sub_field`, and `conditional_field` unless noted)

#### `enforce: true`

Mark this single field enforced. Required keys produce `{:error, %{action: :required_fields, fields: [...]}}`.

```elixir
field :name, :string, enforce: true
```

#### `default: value`

Default value when the user omits the key. **Implies `enforce: false`.**

```elixir
field :tier, :integer, default: 1
field :role, :atom, default: :user
field :active, :boolean, default: false
```

#### `validator: {Mod, :fn}`

Per-field validator. Signature: `fn(field_atom, value) -> {:ok, field, value} | {:error, field, msg}`.

```elixir
defmodule V do
  def is_str(field, v), do: if is_binary(v), do: {:ok, field, v}, else: {:error, field, "not str"}
end

field :name, :string, validator: {V, :is_str}
```

> If omitted but the surrounding module defines `def validator/2`, that one is used automatically — same fallback as `main_validator`.

#### `derive: "..."`

Sanitize + validate mini-language (see Appendix D).

```elixir
field :name, :string, derive: "sanitize(trim, capitalize) validate(string, max_len=20)"
```

#### `struct: AnotherGuardedStructModule`

Embed a separately-defined guarded_struct module. Single value (a map at runtime).

```elixir
defmodule Auth do
  use GuardedStruct
  guardedstruct do
    field :token, :string, derive: "validate(not_empty)"
  end
end

field :auth, :map, struct: Auth
# input: %{auth: %{token: "abc"}} → %User{auth: %Auth{token: "abc"}}
```

#### `structs: AnotherGuardedStructModule`

Embed a list of values, each typed as the external module.

```elixir
field :auth_paths, {:array, :map}, structs: Auth
# input: %{auth_paths: [%{token: "a"}, %{token: "b"}]}
```

#### `structs: true` *(only on `sub_field` and `conditional_field`)*

Mark a `do …`-block sub_field or conditional_field as a list-of-this-shape.

```elixir
sub_field :profile, :map, structs: true do
  field :nickname, :string
end
# input: %{profile: [%{nickname: "a"}, %{nickname: "b"}]}
```

#### `hint: "label"` *(only inside `conditional_field`)*

Surfaces in the error output as `__hint__` so a frontend can tell which conditional branch failed.

```elixir
conditional_field :address, :any do
  field :address, :string, validator: {V, :is_str}, hint: "as_string"
  sub_field :address, :map, validator: {V, :is_map}, hint: "as_object" do
    field :city, :string
  end
end
# Errors carry __hint__: "as_string" | "as_object"
```

#### `priority: true` *(only on `conditional_field`)*

Stop at the first matching child (don't aggregate errors from later children).

```elixir
conditional_field :id, :any, priority: true do
  field :id, :string, derive: "validate(uuid)"
  field :id, :string, derive: "validate(url)"
end
```

#### `error: true` *(on `sub_field`)*

Generate `<Submodule>.Error` per-level, just like the top-level option.

```elixir
guardedstruct error: true do
  sub_field :auth, :map, error: true do
    field :token, :string
  end
end
# Generates: MyMod.Error and MyMod.Auth.Error
```

#### `authorized_fields: true` *(on `sub_field`)*

Per-level rejection of unknown keys.

```elixir
sub_field :auth, :map, authorized_fields: true do
  field :token, :string
end
```

---

### 3. Core keys (cross-field constraints)

These four options form the "core keys" feature. They are checked between `required_fields` and per-field validation, and they all support a `"path::path::path"` mini-syntax.

#### `auto: {Mod, :fn}`

Auto-generate the value at build time. The function is called with no args.

```elixir
field :id, :string, auto: {Ecto.UUID, :generate}
# user passes %{} → %{id: "550e8400-e29b-41d4-a716-446655440000"}
```

#### `auto: {Mod, :fn, default}`

Auto-generate, passing a per-field default value to the function.

```elixir
field :id, :string, auto: {MyMod, :create_id, "user-"}
# calls MyMod.create_id("user-")
```

#### `auto:` with `:edit` builder mode

In `:edit` mode the auto value is **not regenerated** if the user already supplied one — useful for DB updates.

```elixir
TestMod.builder({:root, %{id: "keep-me"}, :edit})
# id stays "keep-me", not regenerated
```

#### `on: "root::other_field"`

Make this field's presence depend on another. The path is `::`-delimited; `root::` means "from the top-level attrs map", anything else means "from the current sub-field's local attrs".

```elixir
field :provider_path, :string, on: "root::provider"
# if provider is missing but provider_path is sent → :dependent_keys error
```

#### `on: "root::deep::path"`

Deep paths into sub-fields are supported.

```elixir
field :rel, :string, on: "root::profile::github"
```

#### `on: "sibling::path"` *(implicit "current scope" prefix)*

Inside a `sub_field`, paths without `root::` resolve from the local attrs map.

```elixir
sub_field :identity, :map do
  field :rel, :string, on: "sub_identity::auth_path::action"
end
```

#### `from: "root::other_field"`

Copy a value from another path if not provided directly.

```elixir
field :username, :string
field :display_name, :string, from: "root::username"
# user sends %{username: "x"} → %{username: "x", display_name: "x"}
```

#### `from:` deep path

```elixir
sub_field :social, :map do
  field :username, :string, from: "root::username"
end
```

#### `from:` with `enforce`/`on` to require source

`from:` itself is non-strict — if both source and target are missing, no error. Combine with `enforce: true` or `on:` to require a source.

```elixir
field :alias, :string, from: "root::name", enforce: true
```

#### `domain: "!path=Type[a, b]::?path=Type[c, d]"`

Cross-field constraint expressed as a string. `!` means **required** dependency, `?` means **optional**. Each clause says "if THIS field has a value, the target path must equal one of the listed values".

```elixir
field :username, :string,
  domain: "!auth.action=String[admin, user]::?auth.social=Atom[banned]"

# If username is sent, auth.action MUST be "admin" or "user",
# and auth.social MAY be :banned (or absent).
```

#### `domain:` with `Equal[…]`

Match a single literal.

```elixir
field :social_equal, :atom,
  domain: "?auth.equal=Equal[Atom>>name]"
# Note: inside Equal[], `>>` replaces `::` because the outer `::` is the clause separator.
```

#### `domain:` with `Either[…]`

Match any of several validators.

```elixir
field :social_either, :atom,
  domain: "?auth.either=Either[string, enum>>Integer[1>>2>>3]]"
```

#### `domain:` with `Custom[Mod, fn]`

Delegate to a user predicate.

```elixir
field :username, :string,
  domain: "!auth.action=Custom[MyApp.Checks, is_ok?]"
```

---

### 4. `builder/2` calling shapes

The generated `builder` accepts three input shapes plus a boolean for raise-on-error.

#### `builder(map)`

Default. Treats `map` as the root attrs.

```elixir
MyMod.builder(%{name: "x"})
```

#### `builder(map, true)`

Raise `MyMod.Error` instead of returning `{:error, _}`. Requires `error: true` on the `guardedstruct`.

```elixir
MyMod.builder(%{name: 1}, true)
# raises %MyMod.Error{}
```

#### `builder({key, attrs})`

Start the build from a sub-path of `attrs`. `key` is `:root`, an atom, or a list of atoms.

```elixir
MyMod.builder({:root, %{name: "x"}})         # same as builder(%{name: "x"})
MyMod.builder({[:profile], full_attrs})       # build the :profile subtree
```

#### `builder({key, attrs, mode})`

Add an `:add` (default) or `:edit` mode flag. `:edit` preserves user-supplied values where `auto:` would otherwise regenerate them.

```elixir
MyMod.builder({:root, %{id: "keep"}, :edit})
```

---

### 5. Generated functions on every produced module

These are not options — they are the public API of every module that uses `guardedstruct` (and every sub_field submodule). Listed for completeness so nothing is missed in the rewrite.

#### `def builder(attrs, error? \\ false)`

Run the full build pipeline. See §4 above.

#### `def keys/0`

Return the list of declared field names.

```elixir
MyMod.keys()
# [:name, :title, :auth]
```

#### `def keys(:all)`

Recursively walk sub_field modules and return a nested keys tree.

```elixir
MyMod.keys(:all)
# [:name, :title, %{auth: [:token, %{path: [:role]}]}]
```

#### `def keys(field)`

Boolean membership test.

```elixir
MyMod.keys(:name)  # true
MyMod.keys(:bogus) # false
```

#### `def enforce_keys/0`

Return the list of enforced field names at this level.

```elixir
MyMod.enforce_keys()
# [:name]
```

#### `def enforce_keys(:all)`

Recursive variant — walks sub_fields too.

#### `def enforce_keys(field)`

Boolean membership test.

#### `def __information__/0`

Returns the metadata map: `%{path: [...], module: __MODULE__, key: :root | atom, keys: [...], enforce_keys: [...], conditional_keys: [...]}`.

```elixir
MyMod.__information__()
# %{path: [], module: MyMod, key: :root, keys: [:name, :auth], …}
```

---

### 6. Things worth surfacing as new option names in the rewrite (proposal)

Most of the items below are in your message — `in`, `depend on`, etc. They're not new features; they're cleaner spellings of options that already exist. Listed here so you can decide which to alias when we ship the Spark version.

| What you wrote | Today's option | Recommendation |
| --- | --- | --- |
| `in` (membership) | `validate(enum=Atom[a::b::c])` | Add a Spark-native alias `in: [:a, :b, :c]` that desugars to the `enum` op. |
| `depend on` (presence dependency) | `on: "root::other"` | Keep `on:`, also accept `depends_on: :other` (atom) and `depends_on: [:profile, :id]` (list path). |
| `copy from` (alias source) | `from: "root::other"` | Same: keep `from:`, also accept `from: :other` and `from: [:profile, :id]`. |
| `default` | `default: value` | No change. |
| `optional / required` | `enforce: true / false` | Add `required: true` and `optional: true` aliases for readability. |
| `one of` | `derive: "validate(enum=…)"` | Same as `in` above. |
| `match` | `derive: "validate(regex=…)"` | Add `regex: ~r/…/` as a top-level alias. |
| `between min..max` | `derive: "validate(min_len=…, max_len=…)"` | Add `between: 3..20`. |
| `equal_to` / `eq` | `derive: "validate(equal=…)"` | Add `equal: value`. |
| `either / one_of_validators` | `derive: "validate(either=[…])"` | Add `either: […]`. |

The point: under Spark we can offer a richer, native-Elixir option vocabulary that compiles down to the same internal op-list, without breaking the legacy string form. Decide at Phase 2.

---

## Appendix F — feature-parity checklist (the commitment)

Tick each box as the Spark rewrite reaches the milestone. **Nothing in the legacy library is dropped.** Every box must be green before v0.1.0 ships.

### Macros / DSL surface

- [ ] `use GuardedStruct`
- [ ] `guardedstruct opts do … end` top-level macro
- [ ] `field name, type, opts`
- [ ] `sub_field name, type, opts do … end` (recursive, unlimited depth)
- [ ] `conditional_field name, type, opts do … end` (recursive, unlimited depth — **new**)

### Top-level options on `guardedstruct`

- [ ] `enforce: true`
- [ ] `opaque: true`
- [ ] `module: SubName`
- [ ] `error: true` → generates `<Mod>.Error` `defexception`
- [ ] `authorized_fields: true`
- [ ] `main_validator: {Mod, :fn}`
- [ ] auto-fallback to `def main_validator/1` in caller module
- [ ] `validate_derive: Mod | [Mod]`
- [ ] `sanitize_derive: Mod | [Mod]`

### Per-field options

- [ ] `enforce: true` per-field
- [ ] `enforce: false` per-field (override block-level `enforce: true`)
- [ ] `default: value`
- [ ] `derive: "..."` legacy string form
- [ ] `derive:` Spark-native list form (new)
- [ ] `validator: {Mod, :fn}`
- [ ] auto-fallback to `def validator/2` in caller module
- [ ] `struct: AnotherMod`
- [ ] `structs: AnotherMod`
- [ ] `structs: true` on `sub_field`
- [ ] `hint: "label"` inside `conditional_field`
- [ ] `priority: true` on `conditional_field`
- [ ] `error: true` on `sub_field` → per-level `<Submod>.Error`
- [ ] `authorized_fields: true` on `sub_field`

### Core keys (cross-field constraints)

- [ ] `auto: {Mod, :fn}`
- [ ] `auto: {Mod, :fn, default}` (one default arg)
- [ ] `auto: {Mod, :fn, [args]}` (multi-arg variant from `auto_core_key/3:1696`)
- [ ] `auto:` honours `:edit` builder mode (no overwrite)
- [ ] `on: "root::path"`
- [ ] `on: "sibling::path"` (local-scope)
- [ ] `on:` deep paths
- [ ] `from: "root::path"`
- [ ] `from: "sibling::path"`
- [ ] `from:` deep paths
- [ ] `domain: "!path=Type[…]"` required clauses
- [ ] `domain: "?path=Type[…]"` optional clauses
- [ ] `domain` `Equal[Type>>value]`
- [ ] `domain` `Either[…]`
- [ ] `domain` `Custom[Mod, fn]`
- [ ] All four core keys work inside `conditional_field`
- [ ] All four work inside list-of-sub_fields (`structs: true`)
- [ ] All four work inside list-of-conditional-field (`structs: true` on conditional)

### Sanitize derives (Appendix D)

- [ ] `trim`, `upcase`, `downcase`, `capitalize`
- [ ] `basic_html`, `html5`, `markdown_html`, `strip_tags`, `tag=<op>` (with `:html_sanitize_ex`)
- [ ] `string_float`, `string_integer` (with and without `:html_sanitize_ex`)
- [ ] Pluggable via `sanitize_derive` config

### Validate derives (Appendix D)

- [ ] Type checks: `string`, `integer`, `list`, `atom`, `bitstring`, `boolean`, `exception`, `float`, `function`, `map`, `nil_value`, `not_nil_value`, `number`, `pid`, `port`, `reference`, `struct`, `tuple`
- [ ] Emptiness/size: `not_empty`, `not_empty_string`, `not_flatten_empty`, `not_flatten_empty_item`, `max_len=N`, `min_len=N`, `range`, `queue`
- [ ] Format: `url`, `geo_url`, `location`, `tell`, `tell=<cc>`, `email`, `email_r`, `string_boolean`, `datetime`, `date`, `regex='…'`, `ipv4`, `uuid`, `username`, `full_name`
- [ ] String-as-number: `string_float`, `some_string_float`, `string_integer`, `some_string_integer`
- [ ] Set/equality: `enum=String/Atom/Integer/Float/Map/Tuple[…]`, `equal=Type::value`, `either=[…]`, `custom=[Mod, fn]`
- [ ] Pluggable via `validate_derive` config

### Builder calling shapes

- [ ] `builder(attrs)` — root, default `:add` mode
- [ ] `builder(attrs, error?)` — second-arg controls raise-on-error
- [ ] `builder({key, attrs})` — start at sub-path
- [ ] `builder({:root, attrs})`
- [ ] `builder({[:nested, :path], attrs})` — list path
- [ ] `builder({key, attrs, type})` — `:add` / `:edit` mode
- [ ] `builder/2` returns `{:error, %{action: :bad_parameters, …}}` on non-map input

### Generated module surface

- [ ] `defstruct …`
- [ ] `@enforce_keys`
- [ ] `@type t()` (and `@opaque t()` when `opaque: true`)
- [ ] `keys/0`, `keys(:all)`, `keys(field)`
- [ ] `enforce_keys/0`, `enforce_keys(:all)`, `enforce_keys(field)`
- [ ] `__information__/0` returns full metadata
- [ ] Each `sub_field` produces a real, callable submodule with the same surface
- [ ] Each `error: true` level produces its own `<Mod>.Error` exception

### Runtime pipeline (order matters; tests assert it)

- [ ] `before_revaluation` (root vs. tuple input)
- [ ] `authorized_fields` (halts on unknown keys)
- [ ] `required_fields` (halts on missing enforce keys)
- [ ] `Parser.convert_to_atom_map` (string keys → atoms, recursive)
- [ ] `auto_core_key`
- [ ] `domain_core_key` (uses original input, not auto-modified)
- [ ] `on_core_key`
- [ ] `from_core_key`
- [ ] `conditional_fields_validating`
- [ ] `sub_fields_validating` (recurses into submodules)
- [ ] `fields_validating` (per-field validator)
- [ ] `main_validating`
- [ ] `replace_condition_fields_derives`
- [ ] `Derive.derive` (sanitize then validate)
- [ ] `exceptions_handler` (raises on `error: true`)

### Conditional field details

- [ ] Multiple `field` children with the same name
- [ ] `field` + `sub_field` mixed children
- [ ] `field` with `struct:` external module child
- [ ] `field` with `structs:` external module child
- [ ] `sub_field` child with `structs: true`
- [ ] `structs: true` on the conditional itself (list-of-conditional)
- [ ] List-of-list of conditional values (nested list flattening)
- [ ] `priority: true` short-circuits on first match
- [ ] `hint:` propagates into error output
- [ ] `derive:` on the conditional itself runs against every input
- [ ] All four core keys work on the conditional itself
- [ ] **Nested `conditional_field` inside `conditional_field`** (issues #7, #8, #25)
- [ ] Synthetic auto-numbered submodule names (`Address1`, `Address2`, `Address3`)
- [ ] Verifier: all children share the conditional's name

### Error output format (must match existing tests byte-for-byte)

- [ ] `{:error, [%{field: …, errors: …, action: …}, …]}` aggregate shape
- [ ] Nested errors carry `errors:` recursively
- [ ] Conditional errors carry `action: :conditionals` and a list of per-child errors with `__hint__`
- [ ] `:halt` semantics: `authorized_fields` and `required_fields` short-circuit
- [ ] `:domain_parameters` / `:dependent_keys` actions
- [ ] `:validator` / `:main_validator` actions
- [ ] All messages routed through `GuardedStruct.Messages` (i18n-pluggable)

### Compile-time guarantees (new in the rewrite)

- [ ] Bad `derive:` string raises `Spark.Error.DslError` at compile, with file:line:column
- [ ] Bad core-key path raises at compile
- [ ] Bad `domain:` expression raises at compile
- [ ] `validator: {Mod, :fn}` MFA check (verifier, post-compile)
- [ ] `auto: {Mod, :fn, …}` MFA check (verifier, post-compile)
- [ ] `from:` path resolves to an existing field (verifier)
- [ ] `on:` path resolves to an existing field (verifier)
- [ ] `struct:` / `structs:` reference is a compiled module (verifier)
- [ ] Conditional-children-share-name verifier
- [ ] Top-level `module:` option still works
- [ ] Source location is preserved in every error

### Tooling (free with Spark)

- [ ] `mix spark.formatter --extensions GuardedStruct.Dsl`
- [ ] `mix spark.cheat_sheets --extensions GuardedStruct.Dsl`
- [ ] `Spark.ElixirSense.Plugin` autocomplete in editors
- [ ] `Spark.Formatter` plugin in `.formatter.exs`
- [ ] Info module: `GuardedStruct.Info` via `use Spark.InfoGenerator`
- [ ] Patchable extension API (third-party libs can extend)

### Existing test files that must turn green unchanged

- [ ] `test/basic_types_test.exs` (205 LOC) — Phase 1
- [ ] `test/derive_test.exs` (846 LOC) — Phase 2
- [ ] `test/validator_derive_test.exs` (544 LOC) — Phase 3
- [ ] `test/global_test.exs` (570 LOC) — Phase 4
- [ ] `test/core_keys_test.exs` (1,035 LOC) — Phase 5
- [ ] `test/conditional_field_test.exs` (2,541 LOC) — Phase 6
- [ ] `test/nested_conditional_field_test.exs` — un-comment, write new tests, all pass — Phase 6
- [ ] `test/nested_sub_field_test.exs` — un-comment, write new tests, all pass — Phase 6
- [ ] `test/guarded_struct_test.exs` (doctests) — Phase 7

### New tests added for the rewrite

- [ ] `test/compile_time_test.exs` — `assert_raise Spark.Error.DslError` for every kind of bad input (bad derive, bad core-key path, bad MFA, etc.)
- [ ] `test/nested_conditional_property_test.exs` (optional, `stream_data`) — random nested conditional trees round-trip cleanly

### Issues closed by the rewrite

- [ ] #1 — VS Code autocomplete (free with Spark)
- [ ] #2 — Single-validation API (`GuardedStruct.Validate.run/3`)
- [ ] #3 — `mix guarded_struct.gen.schema` task
- [ ] #4 — More predefined validators / sanitizers
- [ ] #5 — Virtual fields (`virtual_field` entity)
- [ ] #6 — Erlang record support
- [ ] #7 — Nested conditional fields
- [ ] #8 — Predefined validations 0.1.4 (subsumed by #4)
- [ ] #11 — Dynamic key support
- [ ] #12 — Nested-list validation
- [ ] #25 — Nested conditional (duplicate of #7)
- [ ] Delete the `unsupported_conditional_field/0` message and the two `raise` sites in `lib/derive/parser.ex:40, :56`

### Bugs / surprises in the legacy library to fix during the port

- [ ] `lib/derive/parser.ex:24` — silent `rescue _ -> nil` swallows malformed `derive:` strings; the rewrite raises at compile time
- [ ] `lib/guarded_struct.ex:2271-2293` — long comment about list-of-list of normal fields not being supported; rewrite makes it work
- [ ] `lib/guarded_struct.ex:2243-2249` — synthetic submodule numbering must be deterministic across recompiles
- [ ] Twelve `:gs_*` accumulator attributes — replace with one `dsl_state` map
- [ ] `Module.eval_quoted` racing with `@before_compile` — replaced by transformers
- [ ] String-key vs atom-key edge cases in deeply nested attrs (`Parser.map_keys/2`) — verify and add tests
- [ ] `domain:` parser uses `>>` as a workaround inside `Equal[…]` and `Either[…]`; document, then in the Spark-native form expose a cleaner shape
- [ ] List-of-list of conditional fields can produce logical bugs if not flattened (per the doc warning at line 1227) — write explicit tests, fix
- [ ] Stack traces from compile-time errors point at macro internals — replaced by `Spark.Error.DslError` with source anno

When every box above is ticked, v0.1.0 ships. **No box is optional.**

---

## Appendix G — non-string derive: four ways to write the same thing

You wrote:

> i need none string derive too … kinda hard and user has not autocomplete
> for example: `@derive sanitize(capitalize, trim, etc), validation(something, etc)`
> Or like module type: `@derive Sanitize(capitalize, trim, etc)`
> some ways suggest we level up our project

This appendix is the answer. Three things to clear up first, then four concrete syntax options ranked by autocomplete and ergonomics. The Spark rewrite **supports all four simultaneously**, all desugaring to the same internal op-list. The user picks per-field, per-codebase, or per-team.

### Three ground rules

1. **`@derive` is reserved by Elixir.** It's already the protocol-derivation attribute (`@derive Jason.Encoder; defstruct [:name]`). We can't reuse it without breaking a built-in feature. If you really want module-attribute style, the rewrite can offer `@guarded_derive` or `@derives` — but I argue below this is the worst of the four shapes.
2. **`@derive Sanitize(capitalize, trim)` isn't legal Elixir syntax.** Module-attribute values are *expressions*, and `Sanitize(...)` parses as a function call on a module-name atom — which is invalid because `Sanitize` is an alias, not a module-with-a-`__call__`-fn. To write `Sanitize.trim()` would parse fine, but only as a function call, and that's Option 4 below.
3. **The thing you actually want is autocomplete on rule names.** That requires the rule names to be *real Elixir identifiers* the editor can index — either macro names, atoms in a known schema, or function names. Strings give you nothing.

### Option 1 — Legacy string (kept for backward compat)

```elixir
field :title, :string, derive: "sanitize(trim, upcase) validate(string, max_len=20)"
```

| | |
| --- | --- |
| **Autocomplete** | None inside the string. |
| **Compile-time validation** | Yes — `ParseDerive` transformer raises `Spark.Error.DslError` on typos with file:line:column. |
| **Ergonomics** | Compact. Familiar. |
| **Recommended for** | Existing code. Legacy users on the upgrade path. |

### Option 2 — Inline keyword list (the "atoms-and-tuples" form)

```elixir
field :title, :string,
  sanitize: [:trim, :upcase],
  validate: [:string, max_len: 20, min_len: 3]

# more parameterized rules:
field :role, :atom,
  validate: [:atom, enum: {:atom, [:admin, :user, :banned]}]

field :id, :string,
  validate: [:string, regex: ~r/^[a-f0-9]{32}$/]
```

| | |
| --- | --- |
| **Autocomplete** | Editors complete the keyword keys (`sanitize:`, `validate:`). Atoms inside aren't completed unless we ship a custom Spark schema type, but bad atoms still raise at compile time via the verifier. |
| **Compile-time validation** | Yes — `Spark.Options` validates each atom against the known list; unknown atoms produce a clean error. |
| **Ergonomics** | Reads naturally; one-liner for simple cases; tuples get noisy for parameterized rules. |
| **Recommended for** | One-liners. Fields with two or three rules. |

### Option 3 — Block form on `field` (recommended; best autocomplete)

```elixir
field :title, :string do
  sanitize :trim
  sanitize :upcase
  validate :string
  validate :not_empty
  validate max_len: 20
  validate min_len: 3
end

field :role, :atom do
  validate :atom
  validate enum: {:atom, [:admin, :user, :banned]}
end

field :id, :string do
  validate :string
  validate regex: ~r/^[a-f0-9]{32}$/
end
```

| | |
| --- | --- |
| **Autocomplete** | **Excellent.** `sanitize` and `validate` are real Spark entity macros — ElixirLS / Lexical / Vim-LS index them and give per-rule documentation hovers. The argument atoms (`:trim`, `:upcase`, `:string`, `:not_empty`, …) are completed if we register them as a `:spark_function_behaviour`-style enum. |
| **Compile-time validation** | Yes — every line is its own Spark entity with its own schema. Typos raise at compile time, with `path: [:guardedstruct, :field, :title, :sanitize]` and the offending source line. |
| **Ergonomics** | Verbose for a single rule; ideal for 3+ rules. Reads top-to-bottom. Diff-friendly (one rule per line). |
| **Recommended for** | Default. The Spark-idiomatic way. |

How it works in Spark: we add two child entities to `@field`:

```elixir
@sanitize_entity %Spark.Dsl.Entity{
  name: :sanitize,
  target: %Op{kind: :sanitize},
  args: [:rule],
  schema: [
    rule: [type: {:or, [:atom, {:tuple, [:atom, :any]}, {:keyword_list, [...]}]}, required: true]
  ]
}

@validate_entity %Spark.Dsl.Entity{
  name: :validate,
  target: %Op{kind: :validate},
  args: [:rule],
  schema: [
    rule: [type: {:or, [:atom, {:tuple, [:atom, :any]}, {:keyword_list, [...]}]}, required: true]
  ]
}

@field %Spark.Dsl.Entity{
  name: :field,
  target: Field,
  args: [:name, :type],
  schema: [...],
  entities: [
    sanitize: [@sanitize_entity],
    validate: [@validate_entity]
  ]
}
```

Inside the user's `field … do … end` block, every `sanitize :trim` and `validate :string` is a discrete macro call — exactly what editors and the human eye want. The `ParseDerive` transformer concatenates `field.sanitize ++ field.validate` into the internal op-list, identical to what Option 1 / Option 2 produce. Runtime path is the same.

### Option 4 — Pipe form with module functions (most autocomplete-friendly per character)

```elixir
import GuardedStruct.Sanitize
import GuardedStruct.Validate

field :title, :string,
  derive: trim() |> upcase() |> string() |> max_len(20)

field :role, :atom,
  derive: atom() |> enum(:atom, [:admin, :user, :banned])

field :id, :string,
  derive: string() |> regex(~r/^[a-f0-9]{32}$/)
```

| | |
| --- | --- |
| **Autocomplete** | **Best per character.** Every rule is a function in `GuardedStruct.Sanitize` or `GuardedStruct.Validate`. Editors complete after the first letter. Hover docs show per-function documentation. Refactoring tools can rename rules. |
| **Compile-time validation** | Yes — wrong arity / wrong arg type fails at compile via Elixir's normal type system + Spark schema. |
| **Ergonomics** | Power-user style. Composes cleanly. Slightly noisy parens. |
| **Recommended for** | Library authors who want maximal IDE support. Generated code. |

How it works: `GuardedStruct.Sanitize.trim/0` returns `{:sanitize, :trim}`. `GuardedStruct.Validate.max_len/1` returns `{:validate, {:max_len, 20}}`. Functions like `enum/2` return `{:validate, {:enum, {:atom, [...]}}}`. The pipe just builds a flat list. The schema for `derive:` accepts either `binary()` (Option 1), `keyword()` (Option 2), or `[Op.t()]` (this option). One Spark schema, three input shapes, one parsed output.

### Option 5 — `@derives` sticky-attribute form (decorator-style)

```elixir
guardedstruct do
  @derives "sanitize(trim, capitalize) validate(string, not_empty, max_len=20)"
  field :name, :string

  @derives "validate(integer, max_len=110, min_len=18)"
  field :age, :integer, enforce: true

  field :nickname, :string                                    # no rules — fine

  @derives "sanitize(trim) validate(uuid)"
  sub_field :auth, :map do
    @derives "validate(string, not_empty)"
    field :token, :string
  end
end
```

| | |
| --- | --- |
| **Autocomplete** | None inside the string itself (same as Option 1). |
| **Compile-time validation** | Yes — the wrapper merges the attribute into `opts[:derive]` and the `ParseDerive` transformer raises `Spark.Error.DslError` on typos with file:line:column. |
| **Ergonomics** | Decorator-style, one rule-line per field, field declaration stays short. Reads like `@doc` / `@spec` above a `def`. |
| **Recommended for** | Fields with long rule strings; codebases that prefer Python-decorator-style annotations; teams that already use `@doc`/`@spec` heavily and want consistency. |

#### Why this works (and why I changed my mind)

Elixir already has a well-known **"sticky attribute consumed by the next definition"** idiom. The compiler uses it for:

- `@doc` — consumed by the next `def`
- `@spec` — consumed by the next `def`
- `@impl` — consumed by the next `def`
- `@deprecated` — consumed by the next `def`
- `@typedoc` — consumed by the next `@type`

Modeling `@derives` the same way puts us in good company. A user reading `@derives "..." \n field :x, :string` instantly understands the relationship the same way they understand `@doc "..." \n def f, do: ...`.

#### Naming options (pick one)

The name has to cover **both** sanitize and validate (the existing `derive:` option does, so `@validations` would be wrong — it only suggests validation).

- `@derives` — **recommended.** Plural of the existing `derive:` option. Not reserved (Elixir's reserved attribute is the singular `@derive`, used for protocol derivation). Reads as "the list of derives for this field".
- `@derive_rules` — your original proposal. More explicit, slightly longer. Equally fine.
- `@guarded` — library-branded, short, covers both. Less self-documenting.
- `@field_rules` — clear but the word "rules" is generic; doesn't tie back to `derive:`.
- ~~`@validations`~~ — **rejected**, only covers half (no sanitize).
- ~~`@rules`~~ — too generic; could mean anything.

#### Semantics: one-shot, not sticky

The attribute is **cleared after the next `field` / `sub_field` / `conditional_field` macro** — exactly like `@doc`. This removes the "I forgot to reset it and the next field silently inherited" footgun. If you want the same rules on three consecutive fields, you write the attribute three times. Verbose by design.

```elixir
@derives "validate(string)"
field :a, :string                # consumed here, cleared

field :b, :string                # no rules attached — attribute is empty

@derives "validate(integer)"
field :c, :integer               # consumed here, cleared
```

#### Implementation (~15 lines per macro)

We ship our own thin `field` / `sub_field` / `conditional_field` shim that reads-and-clears the attribute, then delegates to the Spark-generated entity macro:

```elixir
defmacro field(name, type, opts \\ []) do
  quote do
    opts =
      case Module.delete_attribute(__MODULE__, :derives) do
        nil   -> unquote(opts)
        rules -> Keyword.put_new(unquote(opts), :derive, rules)
      end

    GuardedStruct.Dsl.__field__(unquote(name), unquote(type), opts)
  end
end

defmacro sub_field(name, type, opts \\ [], do: block) do
  quote do
    opts =
      case Module.delete_attribute(__MODULE__, :derives) do
        nil   -> unquote(opts)
        rules -> Keyword.put_new(unquote(opts), :derive, rules)
      end

    GuardedStruct.Dsl.__sub_field__(unquote(name), unquote(type), opts, do: unquote(block))
  end
end
```

Same wrapper for `conditional_field`. The Spark internals are unchanged; we're just adding an attribute-reading layer on top.

#### Composition rules

- **Coexists with `derive: "..."`.** If both are present on a single field, the wrapper raises `Spark.Error.DslError` at compile time saying "use one or the other, not both". Pick a style per-team and stick to it.
- **Coexists with Options 2/3/4.** A field can use the block form (`field :x, :type do … end`) for some rules and `@derives` is independent — but mixing on the same field is also a compile-time error to keep things readable.
- **Works inside `sub_field do … end`.** The parent module is still being compiled when the inner `field` runs, so `Module.get_attribute` resolves correctly. No special handling needed.
- **Does not cross `sub_field` boundaries.** Each level of nesting reads from the same module attribute store, but because the attribute is one-shot, an `@derives` outside a `sub_field` is consumed by the next outer `field` — it doesn't leak into the inner block.

### Side-by-side: the same field in all five forms

```elixir
# Option 1 — string
field :name, :string,
  derive: "sanitize(trim, capitalize) validate(string, not_empty, max_len=20, min_len=3)"

# Option 2 — keyword/atom list
field :name, :string,
  sanitize: [:trim, :capitalize],
  validate: [:string, :not_empty, max_len: 20, min_len: 3]

# Option 3 — block (RECOMMENDED for new code)
field :name, :string do
  sanitize :trim
  sanitize :capitalize
  validate :string
  validate :not_empty
  validate max_len: 20
  validate min_len: 3
end

# Option 4 — pipe
import GuardedStruct.Sanitize
import GuardedStruct.Validate
field :name, :string,
  derive: trim() |> capitalize() |> string() |> not_empty() |> max_len(20) |> min_len(3)

# Option 5 — @derives decorator (one-shot, like @doc)
@derives "sanitize(trim, capitalize) validate(string, not_empty, max_len=20, min_len=3)"
field :name, :string
```

All four produce the same internal op-list:

```elixir
[
  {:sanitize, :trim},
  {:sanitize, :capitalize},
  {:validate, :string},
  {:validate, :not_empty},
  {:validate, {:max_len, 20}},
  {:validate, {:min_len, 3}}
]
```

…which feeds the same `GuardedStruct.Derive.run/2` runtime as today.

### Recommendation

All five forms ship. The user picks per-field, per-codebase, or per-team. They all desugar to the same internal op-list before reaching `GuardedStruct.Derive.run/2`, so the runtime cares about exactly one thing.

- **Default in docs and new-code examples: Option 3 (block form).** Idiomatic Spark, best autocomplete out of the box, one rule per line, diff-friendly.
- **Available as syntax sugar: Option 2 (keyword list).** For one-liners and 2-3-rule fields.
- **Available for power users: Option 4 (pipe).** For codegen, refactoring tools, and functional composition.
- **Available for decorator-style codebases: Option 5 (`@derives`).** The cleanest visual layout for fields with long rule strings; matches the `@doc` / `@spec` idiom Elixir users already know. **One-shot semantics** (cleared after each consuming macro) — no footgun.
- **Available for backward compat: Option 1 (legacy string).** Existing 0.0.x users upgrade without touching code; the `ParseDerive` transformer makes their typos surface at compile time too.

A single field cannot mix forms — the wrapper raises `Spark.Error.DslError` if both `derive:` and `@derives` are present, or if `derive: "..."` and a `do ... end` block coexist. Pick a style per-team and stay consistent.

### Levelling-up beyond syntax

You wrote "some ways suggest we level up our project." Beyond derive syntax, here are the wins the rewrite gives us, in rough priority order:

1. **Editor autocomplete inside `guardedstruct do … end`** — free with Spark via `Spark.ElixirSense.Plugin`. No work on our side. Closes issue #1.
2. **Compile-time errors with file:line:column** for every malformed option — `Spark.Error.DslError`. The thing you specifically asked for.
3. **`mix spark.cheat_sheets`** — auto-generated reference docs from the DSL definition. Always in sync with the schema. Replaces the manually-maintained tables in `README.md`.
4. **`mix spark.formatter`** — auto-maintained `locals_without_parens` so users get clean formatting without copy-pasting our config.
5. **Patchable extension** — third-party libs can register their own validators / sanitizers / core-key types without forking. Today this requires application config; under Spark it's first-class.
6. **`mix guarded_struct.gen.schema MyApp.User`** — emit JSON Schema / TypeScript / OpenAPI. Easy because Spark's DSL state is a structured map (today's module-attribute soup makes this hard). Closes issue #3.
7. **Built-in Info module** — `GuardedStruct.Info.fields(MyApp.User)`, `GuardedStruct.Info.fields_required(MyApp.User)`, with proper `@spec`s. Closes most of the use cases for `__information__/0` while keeping it for compat.
8. **Property-based tests** for the derive engine — compile-time-known op list makes `stream_data` round-trip tests trivial.
9. **No more `Module.put_attribute(:gs_*, accumulate: true)` × 12** — one DSL state map, deterministic transformer order, no `@before_compile` race conditions.
10. **Real submodules generated via `Module.create` with `async_compile/2`** — sub_field generation parallelizes; deep trees compile faster.

Pick whichever of these you want first and I'll prioritize accordingly during the phased rollout.

---

## Closing notes

Two things I want you to do before we start writing code:

1. **Read this doc twice.** Specifically §3 (limits), §9 (recursive entities — the unblocker), §10 (compile-time derive — the win you asked for), §14 (phase plan). If anything in those sections is wrong or incomplete, tell me before Phase 1 starts.
2. **Pick a Phase 1 cutoff.** Either "ship Phase 1+2 in v0.1.0-rc1, the rest as -rc2/3/…" or "no rc, ship v0.1.0 only when Phase 7 is green." I lean toward the latter — your existing `0.0.x` users want a single jump.

When you're ready, the next step is creating the `spark-rewrite` branch and starting Phase 1.
