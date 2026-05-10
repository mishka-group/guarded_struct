# GuardedStruct — Roadmap to `v0.1.0`

## Current state

- Test suite: **381/381 passing** (6 properties + 375 tests)
- `mix compile --warnings-as-errors`: clean
- `mix docs`: clean (0 warnings)
- Tier 1 (release-blocking docs + version bump): **complete**
- Tier 2 (DX polish): **complete**
- Tier 3 (infrastructure / quality): **mostly complete** — Real Ash test, Dialyzer, code coverage deferred
- Tier 4 (features beyond master parity): **mostly complete** — niche items (Avro/Protobuf, AJV corners, ElixirLS hover, async/streaming, conditional defaults, `gen.from_json`, upgrade tasks) deferred
- Parity with `master` (legacy `0.0.x` line): complete
- Closed issues: `#1`, `#2`, `#3`, `#5`, `#6`, `#7`, `#8`, `#10`, `#11`, `#25`
- Open issues: `#12` (needs review)
- Branch: `spark-mode`

## Tier 1 — between us and a hex publish ✅ done

### Documentation
- [x] `CHANGELOG.md` entry for `v0.1.0`
- [x] `README.md` rewrite — covers regex fields, `Validate`, `virtual_field`, Splode, schema task, Ash extension, derive extensions, strict mode
- [x] `MIGRATION.md` `0.0.x → 0.1.0`
- [x] LiveBook refresh — Mix.install bumped to 0.1.0, "What's new" table at top, 9 new sections appended
- [x] Hex docs metadata in `mix.exs` `:docs` — `extras:`, `groups_for_modules:`, `nest_modules_by_prefix:`. Clean docs build (0 warnings).
- [x] `mix spark.cheat_sheets` regenerated — both `documentation/dsls/*.md` files updated

### Release hygiene
- [ ] Review issue `#12` and either close or move to a tier
- [ ] `@deprecated` warnings on any 0.0.x-only patterns (audit confirmed: none — full back-compat preserved)
- [x] Bump `@version` in `mix.exs` to `"0.1.0"`
- [ ] Switch the `:igniter` dep from local `path:` back to hex once upstream PR lands (or pin to a fork). Currently still on local path with our `args_for_group/2` fix.

## Tier 2 — high DX wins, small effort ✅ done

- [x] `mix igniter.install guarded_struct` task — adds dep, registers `lint` alias, seeds `derive_extensions: []`, `--strict` and `--strict-paths` flags. 6 tests via Igniter.Test.
- [x] Typo suggestion via `String.jaro_distance/2` — *"Did you mean `:string`?"* against the registry, threshold 0.7, top-3 matches. 3 new tests.
- [x] Verifier for `from:`/`on:` paths existing in schema — opt-in via `config :guarded_struct, strict_core_key_paths: true`. Walks paths through sub_fields and conditionals. 13 tests.
- [x] Cycle detection for `struct:` / `structs:` — post-compile `Verifiers.VerifyNoStructCycles` walks transitively, raises on self-ref or A→B→A. 6 tests.
- [x] Compile-time param-type validation — `Derive.OpParamValidator` catches `max_len="foo"`, negative integers, mistyped tags, etc. 23 tests.

## Tier 3 — infrastructure / quality

- [x] Property-based parser tests via StreamData — 6 properties, caught a real `String.to_charlist`/regex-on-invalid-UTF-8 crash in the parser; fixed by switching to `:binary.bin_to_list` + a top-level rescue.
- [x] Performance benchmarks under `bench/builder_bench.exs` — Benchee runs Simple/FieldHeavy/Nested cases. Baseline: ~130K ops/sec for a 2-field struct.
- [x] Address Elixir 1.19 typing-violation warning — refactored `Derive.Extension.validator/2` to dispatch through a runtime helper instead of a four-clause `case`.
- [ ] Real Ash integration test — pull `:ash` as a `:test` dep, replace `FakeFramework`. Bigger surface change; deferred.
- [ ] Code coverage report (`excoveralls`) — deferred; not currently a release blocker.
- [ ] Dialyzer pass — `:dialyxir` deferred; surfaces unknown count of spec issues, time-unbounded.

## Tier 4 — features beyond master parity

Pick-and-choose; not blocking. Each is independent.

### Production observability
- [x] Telemetry events on `builder/1` — `[:guarded_struct, :builder, {:start, :stop, :exception}]` with `measurements: %{duration, system_time}` and `metadata: %{module, result, error_count}`. 5 tests confirm only top-level builds emit (nested don't). `:telemetry` added as a direct dep.
- [ ] Optional Logger metadata for failed builds — deferred; subsumed by telemetry.

### Serialization & interop
- [x] `@derive Jason.Encoder` auto-generation per struct via `guardedstruct jason: true do …`. 4 tests. `consolidate_protocols: false` in test env to allow late-derive.
- [x] OpenAPI 3.1 emitter — `GuardedStruct.Schema.openapi/1` wraps `json_schema/1` in `components.schemas` envelope. `--format=openapi` flag on `mix guarded_struct.gen.schema`. 5 tests.
- [ ] Avro / Protobuf schema emitters — deferred; very low usage signal.

### Validation power-features
- [x] Diff/patch helpers — `GuardedStruct.Diff.diff/2`, `apply/2`, `equal?/2`. Recurses through sub_fields. 14 tests.
- [ ] Async / streaming list validation — deferred; not requested by users yet.
- [ ] Conditional defaults — deferred; rare power-user feature.
- [ ] Conditional `enforce` — deferred; same.
- [ ] AJV `propertyNames` schema — deferred; rare.
- [ ] AJV `additionalProperties: <schema>` fallback — deferred; rare.
- [ ] Multiple-pattern AND validation in pattern-maps — deferred; first-match-wins is simpler and predictable.

### Tooling
- [x] `mix guarded_struct.gen.struct MyApp.Foo name:string age:integer` scaffolder — Igniter-based, `name!:type` for enforce, type table maps the common ones to derive ops. 5 tests.
- [x] REPL helper `MyStruct.example/0` — auto-generated; uses defaults + type-based fallbacks (`String.t()` → `""`, `integer()` → `0`, etc.). Recurses for sub_fields. 4 tests.
- [x] `@derive_rules "..."` / `@derives "..."` decorator — alternative to inline `derive:` opt. AST walker in the wrapper macro injects into the next field. 6 tests.
- [ ] `mix guarded_struct.gen.from_json` — deferred; chunky.
- [ ] Igniter upgrade tasks (`0.0.x → 0.1.0` auto-rewrite) — deferred; premature without real users on `0.1.0` yet.

### Developer experience
- [ ] ElixirLS / Lexical hover docs for derive op atoms — out of scope (requires upstream LSP work).
- [ ] Better runtime error messages with field paths through nested structures — diffuse work; deferred.

## Out of scope (intentional)

Considered and deliberately deferred:

- **Compile-time op-name validation always-on** instead of opt-in — would break legacy fixtures that intentionally use unknown ops to test the user-extension fallback
- **AJV "single key matching multiple patterns, validating against all"** — rare spec corner; first-match-wins is simpler and faster
- **Generic atom-key support on `dynamic_field`** (vs. existing `:string` / `:existing_atom`) — atom-table-exhaustion DoS vector
- **Mixing atom-keyed and regex-keyed `field`s in one `guardedstruct`** — Elixir struct keys are fixed at compile time; cleanest answer is the compile-time error pointing at nesting
- **Returning Splode errors by default from `builder/1`** — would change the public API contract; opt-in via `GuardedStruct.Errors.from_tuple/1` is enough
- **Sourceror as a runtime/compile-time dep for parser** — `Code.string_to_quoted/1` is already there, faster, and cleaner for parse-and-discard workloads (Sourceror's `__block__` wrapping helped sourceror's source-mapping use case but hurt ours)

## Recommended order

1. **Tier 1 first** — only thing between feature-complete and a clean `mix hex.publish`.
2. Then **Tier 2** — polish the new-user experience before broader adoption.
3. **Tier 3** in any order — quality-of-life and confidence-building.
4. **Tier 4** opportunistically as users request specific items.
