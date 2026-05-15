---
name: guarded-struct
description: Use when working with the GuardedStruct library. Triggers on `use GuardedStruct`, `guardedstruct do ... end`, `Module.builder/1`, `__guarded_change__/1`, `GuardedStruct.AshResource` extension, or files importing `GuardedStruct.{Validate, Diff, Info, Errors}`. Cover declarative field/sub_field/conditional_field/virtual_field/dynamic_field schemas, the `sanitize(...) validate(...)` derive mini-language, per-field/main validators, cross-field `auto`/`from`/`on`/`domain` keys, Ash atomic-mode integration, custom Derive.Extension ops, and Splode error wrapping.
---

# GuardedStruct — full library

Load this skill when editing or generating code that uses `GuardedStruct`,
`GuardedStruct.AshResource`, `GuardedStruct.Derive.Extension`, or any helper
in `GuardedStruct.{Builder, Validate, Diff, Info, Errors}`.

## Entry point

Read the project root `usage-rules.md` for the overview and contract. Topic
deep-dives are split across `usage-rules/*.md`:

| File | Covers |
|---|---|
| `usage-rules/dsl.md` | `field`, `sub_field`, `conditional_field`, `virtual_field`, `dynamic_field`, section options, generated module surface |
| `usage-rules/derive.md` | `sanitize(...) validate(...)` mini-language, full op registry, pipe-friendly `SanitizerDerive.sanitize(value, :op)` |
| `usage-rules/conditional.md` | `conditional_field` runtime dispatch, child-validator contract, error aggregation |
| `usage-rules/validators.md` | `validator: {Mod, :fn}` per-field, `main_validator: {Mod, :fn}` section-level, caller-module fallback |
| `usage-rules/core-keys.md` | `auto`, `from`, `on`, `domain` cross-field rules, pipeline order |
| `usage-rules/extensions.md` | `use GuardedStruct.Derive.Extension`, registration (global / per-module), `:config` interop |
| `usage-rules/ash.md` | `GuardedStruct.AshResource`, `Change`, atomic mode with `Ash.Expr` handling, auto-wire, auto-map cascade |
| `usage-rules/api.md` | `builder/1,2`, `Validate.run/2,3`, `Diff`, `Info`, telemetry events |
| `usage-rules/errors.md` | Canonical `%{field, action, message}` shape, multi-field splitting, Splode wrapping, compile-time `Spark.Error.DslError` |

## Runnable reference

For end-to-end examples of every public feature, open
[`guidance/guarded-struct.livemd`](../../../guidance/guarded-struct.livemd) in
Livebook and `Run all`. The notebook covers DSL declaration, derive ops,
sub_field nesting, conditional dispatch, virtual / dynamic fields, the
standalone `Validate` API, custom `Derive.Extension` ops, Splode wrapping, and
the Ash integration — all runnable in a fresh BEAM.

## Universal contracts (load first)

* `Module.builder/1` returns `{:ok, %Module{}}` or `{:error, [error_map]}`.
  The second element is **always a list** — never a single map.
* Error map shape: `%{field: atom, action: atom, message: String, [errors: [...]]}`.
  Multi-field errors emit one entry per affected field.
* Sanitizer / Validation pipes are pipe-friendly: `value |> sanitize(:op)`.
* All field metadata is baked at compile time. Read via `Mod.__field_meta__(name)`,
  `Mod.__guarded_information__/0`, `Mod.__guarded_fields__/0`. **Do not** call
  `function_exported?` or `Code.ensure_loaded?` on these — they are guaranteed
  to exist on every guarded module.
* The Ash extension exposes `Mod.__guarded_field_name_set__/0` (compile-time
  `MapSet`) for O(1) owned-field checks in `Change.atomic/3`.

## Compile-time guarantees

The Spark layer rejects the module at compile time when:

* `validator: {Mod, :fn}` or `auto: {Mod, :fn}` MFAs don't export the function;
* a `struct:` / `structs:` target creates a cycle;
* a `derives:` string contains an unknown op (and no registered extension declares it);
* a `derives:` string is malformed.

Errors come back as `Spark.Error.DslError` with `path:` and source line.

## What this library does NOT do

* No automatic `defstruct` inside the Ash extension — Ash owns that.
* No `builder/1` generated inside the Ash extension — Ash uses changesets.
* No global `validate/3` walker — every module has its own
  compile-time-baked metadata and dispatch.

## Skill selection guide

If the task touches only one subsystem, prefer the focused skill:

* DSL declaration → `guarded-struct-dsl`
* Derive string / op mini-language → `guarded-struct-derive`
* Conditional fields → `guarded-struct-conditional`
* Ash resource integration → `guarded-struct-ash`
* Custom validate/sanitize ops → `guarded-struct-extensions`
* Runtime helpers / introspection → `guarded-struct-api`
