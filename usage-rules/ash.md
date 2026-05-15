# Ash integration — `GuardedStruct.AshResource`

A Spark DSL extension that plugs the GuardedStruct pipeline into an
`Ash.Resource`. Same `guardedstruct do … end` syntax, but the resource owns its
own struct, attributes, and actions — we contribute only the sanitize / validate
pipeline.

```elixir
defmodule MyApp.User do
  use Ash.Resource,
    domain: MyApp.Domain,
    extensions: [GuardedStruct.AshResource]

  guardedstruct do
    auto_wire true

    field :email, :string,
      derives: "sanitize(trim, downcase) validate(string, not_empty, email_r)"
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

## What the extension adds

The resource gains:

* `__guarded_change__/1` — `(attrs) -> {:ok, transformed} | {:error, [error_map]}`.
* `__guarded_information__/0`, `__guarded_fields__/0`, `__guarded_field_meta__/1`,
  `__guarded_field_name_set__/0` (compile-time-baked MapSet).

The extension does **not** generate `defstruct`, `builder/2`, or an `Error`
module — Ash owns those concerns.

## Wiring `GuardedStruct.AshResource.Change`

`Change` bridges `__guarded_change__/1` into Ash's changeset pipeline.

### Auto-wire (recommended)

```elixir
guardedstruct auto_wire: true do
  field :email, :string, derives: "..."
end
```

The `AutoWireAshChange` transformer adds the change automatically. No
`changes do ... end` block needed.

### Manual

```elixir
changes do
  change GuardedStruct.AshResource.Change
end
```

## Atomic mode

`Change.atomic/3` returns `{:atomic, sanitized_map}` for plain literal inputs,
so update actions stay atomic without `require_atomic? false`. Implementation:

1. Read `changeset.attributes` and `changeset.atomics`.
2. Detect any `Ash.Expr` value on a key our pipeline owns
   (`__guarded_field_name_set__/0`).
3. **Owned + `Ash.Expr`** → `{:not_atomic, reason}` — Ash falls back to imperative.
4. **Owned + literal** → run the pipeline, return `{:atomic, sanitized}`.
5. **Non-owned key** → leave it alone (passes through to Ash's normal handling).

```elixir
# Plain literal — stays atomic
user
|> Ash.Changeset.for_update(:update, %{email: "  New@X.IO  "})
|> Ash.update()
# => updates with email = "new@x.io" via a single SQL statement

# Ash.Expr on an owned field — bails to imperative
user
|> Ash.Changeset.for_update(:update_imperative)  # action with require_atomic? false
|> Ash.Changeset.atomic_update(:login_count, expr(login_count + 1))
|> Ash.update()
```

If the user passes `expr(...)` on an owned field via the default
(`require_atomic? true`) action, Ash itself raises `MustBeAtomic` after seeing
our `{:not_atomic, _}`. Add an `update :update_imperative do require_atomic? false end`
companion action for that path, or move the field outside `guardedstruct`.

## Bulk operations

`batch_change/3` and `atomic/3` both work, so:

* `Ash.bulk_create/3` — runs the pipeline per row.
* `Ash.bulk_update/3` with `strategy: :atomic` — uses `atomic/3`.
* `Ash.bulk_update/3` with `strategy: :stream` — uses `change/3`.

All three produce identical sanitized results.

## Auto-map cascade

Inside the Ash extension, `__guarded_change__/1` returns **plain maps at every
depth** for nested `sub_field` values — never structs. This matches Ash's `:map`
attribute type so output drops directly into `changeset.attributes` without
conversion. Implemented via a process-local flag set at the top of `validate/3`.

## Error shape

Errors from `__guarded_change__/1` follow the canonical
`%{field, action, message}` shape. `Change` converts each into an
`Ash.Error.Changes.InvalidAttribute` exception via `add_error/2`.
