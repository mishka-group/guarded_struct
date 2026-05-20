# Changelog for GuardedStruct 0.1.0

> We are delighted to introduce v0.1.0 — a from-scratch rewrite of the macro core on top of [Spark](https://hex.pm/packages/spark). Every existing 0.0.x public API is preserved. Bump the dep, run `mix deps.get`, and existing tests stay green.

**Tracking PR**: [#13](https://github.com/mishka-group/guarded_struct/pull/13)

### Features:

- Rewrite the 2,910-LOC `defmacro` core on `Spark.Dsl.Extension` with one `:guardedstruct` section, five entities (`field`, `sub_field`, `conditional_field`, `virtual_field`, `dynamic_field`), six transformers, three verifiers [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `Pattern-keyed maps` — `field` whose name is a regex declares a free-form map shape (closes [#11](https://github.com/mishka-group/guarded_struct/issues/11)) [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `virtual_field` — validated through the full pipeline but excluded from `defstruct` (closes [#5](https://github.com/mishka-group/guarded_struct/issues/5)) [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `dynamic_field` — free-form map with passthrough; atom-attack-safe (string keys stay strings) [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add Erlang `Record` support via `validate(record)` and `validate(record=tag)` (closes [#6](https://github.com/mishka-group/guarded_struct/issues/6)) [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `GuardedStruct.Validate` standalone API — `Validate.run/2`, `Validate.field/3,4`, `Validate.partial/2` (closes [#2](https://github.com/mishka-group/guarded_struct/issues/2)) [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add Spark-native custom derive DSL — `use GuardedStruct.Derive.Extension` + `derives do validator/2, sanitizer/2 end` for declarative custom ops [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add per-module `derive_extensions:` opt with `:config` sentinel for in-position merge with global registry [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add compile-time shadow warning when a custom op-name collides with a built-in registered in `Derive.Registry` [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `Splode` error wrapping — `GuardedStruct.Errors.from_tuple/1`, `traverse_errors/2`, `to_class/1`, JSON-serializable shape (opt-in) [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `GuardedStruct.AshResource` extension — same DSL inside `Ash.Resource`; generates `__guarded_change__/1`, `__guarded_information__/0`, `__guarded_fields__/0` under the prefixed namespace [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `GuardedStruct.AshResource.Change` — ready-made `Ash.Resource.Change` module bridging `__guarded_change__/1` into the changeset pipeline [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `auto_wire: true` section option — Spark transformer injects the change into the resource's `changes` section via `Ash.Resource.Builder.add_change/3`; no manual wiring needed [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `batch_change/3` on the Ash change — `Ash.bulk_create/3` and `Ash.bulk_update/3` (with `strategy: :stream`) work end-to-end [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add auto-map cascade for the Ash extension — every nested `sub_field` returns a plain map at every depth (matches Ash's `:map` attribute type) [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add Ash atomic-mode support — `Change.atomic/3` runs the pipeline on plain literal inputs (from both `changeset.attributes` and `changeset.atomics`) and returns `{:atomic, sanitized_map}`; updates stay atomic without `require_atomic? false`. Only the `Ash.Changeset.atomic_update/3` + `Ash.Expr` path falls back to `{:not_atomic, reason}` [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `json: true` section option — auto-derives `Jason.Encoder` (if `:jason` in deps) with fallback to built-in `JSON.Encoder` on Elixir 1.18+ [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `GuardedStruct.Info` — full introspection API: `describe/1`, `field_kind/2`, `enforce?/1,2`, `virtual?/2`, `dynamic?/2`, `sub_module/2`, `conditional_children/2`, collection helpers, section-option shorthands [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `GuardedStruct.Diff` — `diff/2`, `apply/2`, `equal?/2` for audit-log-friendly struct diffing [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `MyStruct.example/0` — REPL helper returning a struct populated with defaults / type placeholders [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add telemetry events — `[:guarded_struct, :builder, :start | :stop | :exception]` on every top-level `builder/1` call [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `@derives` decorator attribute — alternative to inline `derives:` for keeping fields short [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add editor autocomplete inside `guardedstruct do … end` via Spark's ElixirSense plugin (closes [#1](https://github.com/mishka-group/guarded_struct/issues/1)) [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add igniter installer — `mix igniter.install guarded_struct` [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `each=[ops]` combinator on both sanitize and validate — applies inner ops to every element of a list; validate error message reports failing indices.
- Add `optional=[ops]` validator wrapper — passes `nil` through, runs inner ops on non-nil values.
- Add list hygiene sanitizers — `:uniq`, `:compact`, `:reject_empty`, `:sort`.
- Add string hygiene sanitizers — `:squish` (collapse runs of whitespace + trim), `:no_control` (strip ASCII control chars), `:no_zero_width` (strip zero-width unicode).
- Add named regex validators — `:slug`, `:hostname`, `:port_number`, `:hex_color`, `:semver`. Patterns are anchored, bounded, and ReDoS-safe; compiled once at module load.
- Add `{:clamp, [min, max]}` sanitizer — snap out-of-range numbers to the nearest bound.
- Add `{:default_when_nil, value}` / `{:default_when_empty, value}` sanitizers — fill missing values in the pipeline.
- Compile-time param shape validation extended to every new parameterised op via `OpParamValidator`.
- Localised error messages added through the `Messages` callbacks for `slug`, `hostname`, `port_number`, `hex_color`, `semver`, and `each`.


### Refactors:

- Move every static-string parse to compile time — derive op-strings, `from:`/`on:` paths, `domain:` patterns are now parsed once during compilation; the runtime reads pre-built op-maps from `__fields__/0` [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Pre-evaluate `enum=Map[…]` / `enum=Tuple[…]` / `equal=Map::…` operands at compile time — zero `Code.eval_string` on the runtime hot path [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Replace plain-macro `validator/2` and `sanitizer/2` with proper Spark entities under `derives do ... end` block — Spark.Formatter handles paren-stripping consistently with the rest of the DSL [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Surface compile-time warnings via the transformer's documented `{:warn, dsl_state, warnings}` return shape instead of `IO.warn/2` — shadow detection in `Derive.Extension.Transformers.Codegen` and legacy-`derive:` deprecation in `Transformers.ParseDerive` both flow through Spark, so warnings appear at the user's source line and the DSL state remains the transformer's only side effect [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Rename `__guarded_validate__/1` → `__guarded_change__/1` on the Ash extension — name reflects that the function transforms (sanitize, auto-fill) as well as validates [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Rename `derive:` option to `derives:` (plural) — aligns with the `@derives` decorator; legacy `derive:` still works but the transformer emits a compile-time deprecation warning through Spark's `{:warn, ...}` transformer return [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Rename `jason: true` section option to `json: true` — option now derives whichever JSON encoder is available (Jason or built-in) [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Extract test fixtures (Ash resources + custom-derive modules) to top-level modules in `test/support/` so Spark.Formatter applies paren-removal and section-ordering rules uniformly [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Normalize the error wire format — every `{:error, …}` from `builder/1`, `__guarded_change__/1`, `Validate.run/2`, `Validate.field/3,4`, `Validate.partial/2` and the Ash `Change` is **always** `{:error, [error_map, ...]}`. Each error map follows the canonical shape `%{field: atom, action: atom, message: String, [errors: [...]]}`. `:required_fields` and `:authorized_fields` emit one error **per affected field** instead of one map with a `fields:` list. `:bad_parameters` carries `:field => :__root__` [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Flip `GuardedStruct.Derive.SanitizerDerive.sanitize/2` to pipe-friendly `(value, op)` arg order — was `(op, value)`. Applies project-wide: `Extension.dispatch_sanitize/2,3`, the generated `__sanitize__/2` callback on extension modules, and any user-supplied `:sanitize_derive` module's `sanitize/2` function follow the same convention. Internal hot path now reduces with `Enum.reduce(ops, value, fn op, acc -> sanitize(acc, op) end)` [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Bake compile-time predicates on every guarded module — `__guarded_has_validator__/0`, `__guarded_has_main_validator__/0`, `__guarded_error_module__/0`, `__guarded_field_meta__/1` (and Ash's `__guarded_field_name_set__/0` MapSet) — drops every `function_exported?` / `Code.ensure_loaded?` call from the runtime hot path [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Cache `GuardedStruct.Derive.Extension.registered_extensions/0` in `:persistent_term`, keyed by raw app config; auto-invalidates when config changes. New `clear_cache/0` helper for test setup [#13](https://github.com/mishka-group/guarded_struct/pull/13)

### Bugs:

- Fix nested `conditional_field` — works to arbitrary depth via `recursive_as: :conditional_fields` (closes [#7](https://github.com/mishka-group/guarded_struct/issues/7), [#8](https://github.com/mishka-group/guarded_struct/issues/8), [#25](https://github.com/mishka-group/guarded_struct/issues/25)) [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Restore i18n via `GuardedStruct.Messages.translated_message/1,2` for orchestration-layer errors (`authorized_fields`, `required_fields`, `:on` / `:domain` core keys, list-builder errors) — all 14 message callbacks reachable again [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Fix `__information__/0` to populate `conditional_keys` with actual conditional-field names (was always `[]`) [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Fix `MyStruct.Error.message/1` to match master's format and use `translated_message(:message_exception)` for i18n [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Unblock the legacy `Parser` `raise` sites that prevented nested `conditional_field` from compiling [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Surface malformed `derives:` strings as `Spark.Error.DslError` with file:line — previously swallowed by a `rescue _ -> nil` and silently produced no validation [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Fix re-entrancy in the auto-map cascade — process-dict flag is saved+restored across nested `validate/3` calls so a validator callback can recursively validate without clobbering outer state [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Fix `Logger.configure(level: :warning)` global side-effect in `test_helper.exs` — replaced with `@moduletag capture_log: true` on Ash test modules [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Parser silently dropped the entire derive string when a `regex=<pattern>` op contained unquoted special characters (`^`, `[`, `+`, `$`, …). Fixed via `quote_regex_values/1` pre-processor that wraps the pattern in `"…"` before AST conversion.


### Tests:

- Add 743+ tests (up from 146 in 0.0.4), including 6 property-based tests via `stream_data` [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add real Ash 3.x integration suite — ETS data layer, end-to-end `Ash.create/1`, `Ash.update/1`, `Ash.bulk_create/3`, `Ash.bulk_update/3` [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `test/ash_integration_test.exs` atomic-mode coverage — end-to-end create/update through Ash with sanitize/validate semantics intact under atomic SQL [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `test/info_test.exs` — 38 tests covering every introspection helper including `describe/1` consolidated dump [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `test/derive_extension_shadow_warning_test.exs` — 9 tests for compile-time shadow detection [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `test/derive_extensions_per_module_test.exs` — 19 tests for per-module opt resolution including the `:config` sentinel [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `test/jason_encoder_test.exs` — Jason + built-in JSON encoder coverage with nested sub_field [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `test/telemetry_test.exs` — start/stop/exception event coverage, including nested-build inheritance [#13](https://github.com/mishka-group/guarded_struct/pull/13)

### Docs:

- Add full LiveBook walkthrough at [`guidance/guarded-struct.livemd`](./guidance/guarded-struct.livemd) with runnable end-to-end examples [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add auto-generated DSL cheat sheets at `documentation/dsls/` via `mix spark.cheat_sheets` [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `mix lint` and `mix cheat` aliases — wrap `spark.formatter` + `format` and `spark.cheat_sheets` [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add "Atom-attack safety" section to the `GuardedStruct` module @moduledoc covering the dynamic_field / pattern-keyed map threat model [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add LLM agent context — root [`usage-rules.md`](./usage-rules.md) plus topic-scoped sub-rules at [`usage-rules/dsl.md`](./usage-rules/dsl.md), [`derive.md`](./usage-rules/derive.md), [`conditional.md`](./usage-rules/conditional.md), [`validators.md`](./usage-rules/validators.md), [`core-keys.md`](./usage-rules/core-keys.md), [`extensions.md`](./usage-rules/extensions.md), [`ash.md`](./usage-rules/ash.md), [`api.md`](./usage-rules/api.md), [`errors.md`](./usage-rules/errors.md) (compatible with [ash-project/usage_rules](https://github.com/ash-project/usage_rules); consumers run `mix usage_rules.sync` and address sub-rules as `guarded_struct:dsl`, `guarded_struct:ash`, etc.) [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add [skills.sh](https://www.skills.sh/)-compatible `SKILL.md` files under `.claude/skills/` — one per subsystem (`guarded-struct`, `-dsl`, `-derive`, `-conditional`, `-ash`, `-extensions`, `-api`) with YAML frontmatter triggers so Claude Code / Cursor / Copilot auto-load the right context [#13](https://github.com/mishka-group/guarded_struct/pull/13)

### Internals dropped:

- Remove `builder/4` `@doc false` form (with `(actions, key, type, error)` arity) — replaced by an internal runtime helper [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Remove `register_struct/4`, `__field__/6`, `__type__/2`, `delete_temporary_revaluation/1`, `create_builder/1`, `create_error_module/0` [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Remove the 12 `gs_*` accumulator module attributes (`gs_fields`, `gs_types`, `gs_enforce_keys`, etc.) — replaced by Spark DSL state [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Remove `parser/3` (the conditional variant of `Parser.parser`), `elements_unification/2`, `find_node_tags/1`, `add_parent_tags/3`, `conds_list/2`, `find_conds_children_recursive/2` [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Remove `Derive.pre_derives_check/3`, `get_derives_from_success_conditional_data/1`, `error_handler/2`, `halt_errors/1`, the alternate-shape `derive/1` clauses [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Remove `Messages.unsupported_conditional_field/0` and `Messages.parser_field_value/0` callbacks (dead code after the nested-conditional fix) [#13](https://github.com/mishka-group/guarded_struct/pull/13)

### Dependencies:

- Add `{:spark, "~> 2.7"}` (runtime — DSL framework) [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `{:splode, "~> 0.3"}` (runtime — error class hierarchy for opt-in wrapper) [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `{:telemetry, "~> 1.0"}` (runtime — builder events) [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `{:sourceror, "~> 1.7", only: [:dev, :test]}` (required by Spark.Formatter) [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `{:igniter, "~> 0.8", only: [:dev, :test]}` (installer mix task) [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- Add `{:ash, "~> 3.0", only: [:dev, :test]}` (real Ash integration suite — not a runtime dep) [#13](https://github.com/mishka-group/guarded_struct/pull/13)
- All optional deps unchanged (`html_sanitize_ex`, `email_checker`, `ex_url`, `ex_phone_number`, `sweet_xml`) [#13](https://github.com/mishka-group/guarded_struct/pull/13)

---

# Changelog for GuardedStruct 0.0.4

### Bugs:

- Fix deprecated code from Elixir 1.18

### Features:

- Support overridable messages for the `GuardedStruct` module with support for multiple languages

---

# Changelog for GuardedStruct 0.0.3

### Bugs:

- Fix deprecated code from Elixir 1.18.0-rc.0

---

# Changelog for GuardedStruct 0.0.2

### Bugs:

- Support charlists sigil warning and keep backward compatibility for charlist regex

---

# Changelog for GuardedStruct 0.0.1

> We are delighted to introduce our first standalone release of GuardedStruct — extracted from the Mishka developer tools library.
>
> **For more information please see**: https://mishka.tools

### Features:

- Detach from the Mishka developer tools library

### Refactors:

- Remove optional libraries (must be enabled by the user)
- Improvements in some tests
