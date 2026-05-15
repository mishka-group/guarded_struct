---
name: guarded-struct-ash
description: Use when working with an `Ash.Resource` that has `extensions: [GuardedStruct.AshResource]` — i.e. any file declaring `guardedstruct` inside an Ash resource, anything wiring `GuardedStruct.AshResource.Change`, or anywhere `Ash.update`/`Ash.bulk_update`/`Ash.Changeset.atomic_update` is involved on a resource that uses the extension. Covers auto-wire, atomic mode with `Ash.Expr` handling, the `:not_atomic` bail, `require_atomic? false` fallback path, and the auto-map cascade.
---

# Ash integration

Reference: `usage-rules/ash.md`.

## Resource template

```elixir
defmodule MyApp.User do
  use Ash.Resource,
    domain: MyApp.Domain,
    extensions: [GuardedStruct.AshResource]

  guardedstruct do
    auto_wire true   # injects GuardedStruct.AshResource.Change automatically
    field :email, :string, derives: "sanitize(trim, downcase) validate(email_r)"
  end

  attributes do
    uuid_primary_key :id
    attribute :email, :string, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read, :destroy, :create]
    update :update, accept: [:email]
  end
end
```

`auto_wire: false` (default) requires a manual `changes do change GuardedStruct.AshResource.Change end` block.

## Atomic mode — three behaviours

`Change.atomic/3` inspects every key in `changeset.attributes` and
`changeset.atomics`. For each owned field (in `__guarded_field_name_set__/0`):

| Input | Result |
|---|---|
| Plain literal in `attributes` or `atomics` | Sanitize via the pipeline, return `{:atomic, sanitized_map}`. UPDATE stays atomic. |
| `Ash.Expr` in `atomics` (e.g. `expr(counter + 1)`) | Return `{:not_atomic, reason}`. Ash falls back to imperative `change/3` if the action has `require_atomic? false`; otherwise Ash raises `Ash.Error.Framework.MustBeAtomic`. |

Non-owned keys are passed through untouched — `expr(now())` on a plain Ash
attribute (not in `guardedstruct`) stays atomic.

## Three options when an atomic expression is needed

* **Accept the fallback** — declare a companion action with `require_atomic? false`.
  `atomic/3` bails, Ash runs `change/3` imperatively, update still succeeds.
* **Pass a plain value** — compute in Elixir, pass via `attributes`. Stays
  atomic, pipeline validates.
* **Move the field outside `guardedstruct`** — `atomic_update(_, expr(... + 1))`
  works without going through our pipeline.

## Bulk

* `Ash.bulk_create/3` → uses `batch_change/3` (per-row pipeline).
* `Ash.bulk_update/3` with `strategy: :atomic` (default) → uses `atomic/3`.
* `Ash.bulk_update/3` with `strategy: :stream` → uses `change/3`.

All three produce identical sanitized results.

## Auto-map cascade

`__guarded_change__/1` returns **plain maps** at every depth for nested
sub_fields — never structs. This matches Ash's `:map` attribute type so output
drops directly into `changeset.attributes` without conversion. Set via a
process-local flag at the top of `validate/3`; concurrency-safe.

## Don'ts

* Don't add `require_atomic? false` to every update action — most updates are
  atomic-safe by default with this extension. Only add it on actions that need
  to accept `Ash.Expr` values for owned fields.
* Don't write `defstruct` or `builder/1` in the resource module — Ash provides
  both. The extension only adds `__guarded_change__/1` and metadata.
* Don't rely on `function_exported?(MyResource, :__guarded_field_name_set__, 0)`
  — it's always defined on resources using this extension.

## Companion modules

* `GuardedStruct.AshResource.Info` — Ash-flavoured introspection
  (`fields/1`, `field/2`, `validate/2`, etc.).
* `GuardedStruct.AshResource.Change` — the bridge change module.
