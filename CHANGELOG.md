# Changelog for GuardedStruct 0.1.4

> The documented behaviour is now the real behaviour: every option and op the docs promised works, and a derive string that used to be dropped silently fails to compile.

**Tracking PR**: [#15](https://github.com/mishka-group/guarded_struct/pull/15)

### Bugs:

- Fix `main_validator: {Mod, :fun}` on the section and on a `sub_field` — it was never called, only a `main_validator/1` defined in the module ran. The option now wins; a `main_validator/1` in the module still runs when the option is not set
- Fix the `validate_derive` / `sanitize_derive` section options — only the application config was used at runtime. The modules of the section option (and of its `sub_field`s) are tried first, the application config serves the ops they leave unhandled. `Validate.field/4` and `Validate.partial/2` read them too
- Fix `sanitize(default_when_nil=...)` — it never filled a `nil` or missing field because derives skip `nil`. It now does, and the ops written after it run on the default; every other op still skips `nil`
- Fix the derive parser silently dropping operands: `equal=Type::value` (`equal=Integer::1`, `String::`, `Float::`, `Atom::`, `Map::`, `Tuple::`), negative numbers (`min_len=-2`, `clamp=[-10, 10]`, `default_when_empty=-1`), floats and other literals (`default_when_nil=false`). They are parsed now; an operand that can't be parsed, a derives string the Elixir parser refuses (such as `enum=Atom[a, b]`) and `enum=Integer[...]` / `equal=Integer::...` values that aren't numbers raise `Spark.Error.DslError` at compile time. A field whose derives were all dropped is no longer set to `nil`
- Fix a `validate()` / `sanitize()` group with no ops setting the field to `nil` — the value is kept
- Fix `equal=String::value` never matching once pre-evaluated
- Fix `builder/1` turning every struct other than `Date`, `DateTime` and `NaiveDateTime` into a plain map, which made `validate(time_struct)` / `validate(struct)` fail for `%Time{}` / `%URI{}`. Structs are kept intact
- Fix extension ops inside `each=[...]` / `optional=[...]` being a compile error (`unknown validate op`) while `either=[...]` accepted them. Ops of the module's `derive_extensions:`, of the global config and (when a `validate_derive` / `sanitize_derive` is set) of those modules are accepted
- Fix `domain:` rules not being evaluated inside a `GuardedStruct.AshResource` resource — the extension now runs `ParseDomain` (and `ParseCoreKeys`) like the standalone DSL
- Fix the Ash extension not accepting `guardedstruct opts do … end`, `sub_field name, type, opts do … end` and `conditional_field name, type, opts do … end` — `undefined function sub_field/4` — although the docs show them and `use GuardedStruct` takes them. They work in a resource now; the `@derives` decorator stays standalone-only
- Fix `dynamic_field` inside a `sub_field` not being identity-preserved: the parent converted its keys (`"role"` came back as `:role`). Keys stay as given in a `sub_field` of any depth, a list `sub_field`, a `struct:` module and a `conditional_field`'s `sub_field`; `Validate.partial/2` keeps them too
- Fix `GuardedStruct.Info.fields/1` raising `KeyError` on a pattern-keyed (regex) module — it lists the patterns. `field_kind/2` returns `:pattern_field` for a key a pattern matches, and `field/2` / `field?/2` follow the patterns
- Fix `enforce_keys(:all)` listing every key of a `sub_field` instead of only the enforced ones
- Fix the `validator:` error of a pattern-keyed field missing `:field` — it carries `field: :__map__` like the other errors of the module

### Docs:

- Fix `auto` being documented as filling only missing values — in `:add` mode it replaces a value the caller sent; `:edit` keeps it. The Livebook's example labels were inverted
- Fix `from` being documented as filling a field only when it is unset — a source that holds a value replaces the field's own value, a missing or `nil` source keeps it
- Fix `on` being documented as comparing a value (`on: "role=admin"`) and as emitting a `:domain_parameters` error — it only checks that the path is present and emits `:dependent_keys`; `domain` compares the value
- Fix `priority: true` being documented on a child — it works on the `conditional_field` and keeps only the first child's error when none match
- Fix the README example that wrote a `sanitize(...)` group after `validate(...)`; every `sanitize` group runs before every `validate` group
- Fix the verifiers being documented as rejecting the module — they only warn at compile time and the module still compiles
- Fix `usage-rules/api.md`: `Diff.diff/2` returns `{:changed, old, new}` and the raising form is `builder(attrs, true)`
- Fix the `domain` example `Atom[admin::moderator]` to `Atom[admin, moderator]`
- Fix `no_control` being documented as stripping every control character — tab, LF and CR are kept
- Fix `html_sanitize_ex` being documented as optional; the minimum is Elixir 1.17 and the Livebook's `Mix.install` versions install
- Fix the `custom=[Mod, :ok?]` sample in `usage-rules/ash.md` (the op was dropped); document `main_validator` on a `sub_field`, the `validate_derive` / `sanitize_derive` precedence, the operand forms and `Info` on pattern-keyed modules
- Document `main_validator`, `validate_derive` and `sanitize_derive` in the DSL cheat sheets

### Tests:

- Add the tests for each of the fixes above: `derive_operands_test.exs`, `derive_section_options_test.exs` and new cases in the parser, op-param, registry, derive, extension, validator, Ash, dynamic, Info and pattern-map suites, `core_keys_test.exs` for `from`, `on` and `domain`, and the option forms of the Ash extension in `ash_resource_test.exs` and `ash_resource_change_test.exs`

### Dependencies:

- Update `ash` 3.33.11 → 3.36.1, `spark` 2.7.3 → 2.7.8, `sourceror` 1.12.3 → 1.12.4 (and `decimal` 3.2.0, `ex_ast` 0.16.0, `makeup` 1.2.3, `req` 0.7.5, `spitfire` 0.4.3, `sweet_xml` master)
- Raise the dev/test requirements to `{:ash, "~> 3.36"}` and `{:sourceror, "~> 1.12"}`

---

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
- Add string hygiene sanitizers — `:squish` (collapse runs of whitespace + trim), `:no_control` (strip ASCII control chars, but keep tab, LF and CR), `:no_zero_width` (strip zero-width unicode).
- Add `:rich_text_safe` sanitizer — sugar that composes `:no_zero_width` + `:no_control` in one named op for template/content/bio fields; non-binary inputs pass through untouched.
- Add named regex validators — `:slug`, `:hostname`, `:port_number`, `:hex_color`, `:semver`. Patterns are anchored, bounded, and ReDoS-safe; compiled once at module load.
- Add `:language_code` validator — BCP-47 / ISO 639-1 shape (e.g. `en`, `en-US`, `zh-Hant`, `pt-BR`). Anchored regex, case-insensitive, primary 2–3 letters + optional `-subtag` segments (2–8 alnum each).
- Add datetime shape validators — `:utc_datetime`, `:naive_datetime`, `:date_struct`, `:time_struct`. Each accepts both the matching Elixir struct **and** the ISO-8601 binary form, so the same op covers Ash struct inputs and raw string inputs from JSON/form bodies.
- Add datetime comparison validators — `:past_datetime`, `:future_datetime`. Inclusive semantics: "now" passes both, so callers never trip on clock skew between submit and validate.
- Add `:ipv6` validator — accepts only literal v6 addresses; rejects v4-as-v6 by requiring at least one `:` character before handing off to `:inet.parse_ipv6_address/1`.
- Add `:ip` validator — accepts either v4 or v6 form; thin wrapper that tries v4 first, falls back to v6.
- Add `{:clamp, [min, max]}` sanitizer — snap out-of-range numbers to the nearest bound.
- Add `{:default_when_nil, value}` / `{:default_when_empty, value}` sanitizers — fill missing values in the pipeline.
- Compile-time param shape validation extended to every new parameterised op via `OpParamValidator`.
- Localised error messages added through the `Messages` callbacks for `slug`, `hostname`, `port_number`, `hex_color`, `semver`, `each`, `language_code`, `utc_datetime`, `naive_datetime`, `date_struct`, `time_struct`, `past_datetime`, `future_datetime`, `ipv6`, and `ip`.


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
- `def validate/3` clauses in `ValidationDerive` were interrupted by four `defp` helpers wedged between them, triggering the compiler's "clauses of the same name should be grouped together" warning and risking mis-dispatch of later clauses. All helpers moved below the catchall; added a dispatch-regression test that probes 43 op atoms with deliberately-bad inputs and asserts none fall through to the catchall.
- Per-element `:each` errors now carry an `__index__:` key after flattening. Previously errors from list-element validation came back as a nested `{:children, [...]}` 5-tuple with no way to tell which element failed; `call/3` now flattens children into the top-level errors list with the originating index attached, so callers can pinpoint which list position broke.


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
- `html_sanitize_ex` is a required dependency; the optional deps are unchanged (`email_checker`, `ex_url`, `ex_phone_number`, `sweet_xml`) [#13](https://github.com/mishka-group/guarded_struct/pull/13)

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
