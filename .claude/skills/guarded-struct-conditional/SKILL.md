---
name: guarded-struct-conditional
description: Use when declaring or debugging a `conditional_field` block — multi-shape fields that resolve to one child based on a per-child `validator:` MFA. Covers child dispatch order, `priority: true`, `structs: true` for list iteration, error aggregation under `action: :conditionals`, and arbitrarily-deep nesting.
---

# `conditional_field`

Reference: `usage-rules/conditional.md`.

## Anatomy

```elixir
conditional_field :owner, any() do
  field :owner, struct(), struct: Person, validator: {Checks, :is_map_data}
  field :owner, String.t(), validator: {Checks, :is_string_data},
        derives: "validate(url)"
end
```

* Every child shares the parent's `:name`.
* Each child must declare `validator: {Mod, :fn}`.
* The MFA is called as `Mod.fn(field_name, value)` and returns either
  `{:ok, name, value}` (this child wins) or `{:error, name, reason}` (try next).

## Modifiers

| Modifier | Effect |
|---|---|
| `priority: true` on one child | Short-circuit when this child wins. ≤ 1 per parent. |
| `structs: true` on a child or inner conditional | Iterate a list; apply children element-wise. |
| `hint: "label"` on a child | Propagated into error maps as `__hint__:` for debugging. |
| `validator: {VAL, :is_map_data}` on an inner conditional | Gate descent: only enter when input is a map. |

## Error aggregation

When **no child matches**, the parent emits:

```elixir
%{
  field: :owner,
  action: :conditionals,
  errors: [
    %{field: :owner, action: :validator, __hint__: "as-map",    message: "It is not map"},
    %{field: :owner, action: :validator, __hint__: "as-string", message: "It is not string"}
  ]
}
```

Nested conditionals add one more `:conditionals` aggregator per level.

## Descent semantics — common pitfall

The runtime feeds the **same value** to every child. So:

```elixir
conditional_field :choice, any() do
  field :choice, String.t(), validator: {Checks, :is_string_data}
  conditional_field :choice, any(), validator: {Checks, :is_map_data} do
    field :choice, :integer, validator: {Checks, :is_int_data}
  end
end
```

The inner `:integer` child is **unreachable**: entering the nested conditional
requires `is_map_data` to succeed (value is a map), but the integer matcher
needs an integer. Same value flows through both levels.

To reach the integer: drop the map gate, or use `structs: true` to iterate
a list of mixed-type elements, or restructure with `sub_field`.

## Nested depth

Works to arbitrary depth (closes issues #7, #8, #25 from the legacy 0.0.x
parser). Each level pattern-matches as a separate `conditional_field` entity
with its own children.

## Test patterns

Property-style: assert that **one** `:conditionals` aggregator appears at the
expected level, and that the inner `__hint__` set covers every child you
expect to have been tried. Avoid exact-shape `=` matches — child evaluation
order is documented but tests should be order-independent.
