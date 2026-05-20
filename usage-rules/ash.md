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

## `each=[<type-op>]` is dead on typed array attributes

`Ash.create/1` runs **attribute casting before changes**. When an attribute
is typed (e.g. `{:array, :string}`, `{:array, :integer}`), Ash casts every
element through the inner type at the attribute layer. Elements that fail
cast surface as `Ash.Error.Changes.InvalidAttribute` with `path: [<index>]`,
and the bad value is stripped from `changeset.attributes` before
`GuardedStruct.AshResource.Change` runs.

So a derive like

```elixir
field :allowed_origins, {:array, :string},
  derives: "validate(each=[string])"
```

never produces a GS-level error — Ash has already rejected (or removed)
anything non-string before our pipeline sees it. The op compiles, looks
meaningful, but contributes zero safety.

Use `each=[…]` for content checks Ash can't express:

```elixir
derives: "validate(each=[hostname])"          # ✓ runs through Ash
derives: "validate(each=[regex=^[a-z]+$])"    # ✓ runs through Ash
derives: "validate(each=[slug])"              # ✓ runs through Ash
derives: "validate(each=[custom=[Mod, :ok?]])" # ✓ runs through Ash
```

Not for type checks Ash already does at the attribute layer. The same
applies to other Ash typed scalars — `validate(string)` on a `:string`
attribute, `validate(integer)` on an `:integer` attribute, etc. — they're
redundant under Ash because the cast catches type mismatches first.

## Action validate-before-change order

Ash's action lifecycle runs the directives declared inside the action
in this order:

1. attribute cast
2. attribute constraint validations (`min_length`, `min`, `one_of`, …)
3. action-level `validate` directives (`validate present([…])`, custom
   `Ash.Resource.Validation` modules)
4. action-level + global `change` directives (this is where
   `GuardedStruct.AshResource.Change` lives)

That means a custom `Ash.Resource.Validation` you've added on the same
field **sees the raw user input, not the sanitized version**:

```elixir
create :create do
  validate {MyApp.DomainValidator, []}       # runs FIRST — sees "  HTTPS://X.COM  "
  # ...
end

guardedstruct auto_wire: true do
  field :host, :string,
    derives: "sanitize(trim, downcase) validate(hostname)"  # runs AFTER
end
```

`DomainValidator` will reject `"  HTTPS://X.COM  "` for the leading space
even though our sanitize would have cleaned it up. There is no opt-in
setting on `guardedstruct` to flip this — Ash treats validates as guards
that decide whether to run the action, by design.

Two ways to get sanitize-before-validate semantics:

**Option A — fold the format check into GS (single layer).** Drop the
custom `Ash.Resource.Validation` and re-express the rule as a GS validate
op so it runs in the same pass as the sanitize:

```elixir
create :create do
  # validate {MyApp.DomainValidator, []}   ← removed
end

guardedstruct auto_wire: true do
  field :host, :string,
    derives: "sanitize(trim, downcase) validate(hostname)"
end
```

**Option B — keep both, accept the order.** Useful when the Ash-level
validation produces a helpful error message you want to keep and the
field is normally clean by the time it reaches the action. In that case
the GS sanitize layer mainly helps on edges the validator allows through
(e.g. de-duplication of valid items inside an array).
