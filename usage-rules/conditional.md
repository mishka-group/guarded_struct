# `conditional_field` — runtime child dispatch

A `conditional_field` lets a single name resolve to one of several shapes
depending on the input value. Children share the parent's name; the runtime
walks them in declaration order and the first child whose `validator:` returns
`{:ok, ...}` wins. Nesting and `:structs` lists are both supported.

```elixir
conditional_field :actor, any() do
  field :actor, struct(), struct: Actor, validator: {VAL, :is_map_data}

  conditional_field :actor, any(), structs: true, validator: {VAL, :is_list_data} do
    field :actor, struct(), struct: Actor, validator: {VAL, :is_map_data}
    field :actor, String.t(), validator: {VAL, :is_string_data},
          derives: "validate(url)"
  end

  field :actor, String.t(), validator: {VAL, :is_string_data},
        derives: "validate(url)"
end
```

## Child-validator contract

Each child must declare `validator: {Mod, :fn}`. The MFA is called as
`Mod.fn(field_name, value)` and returns one of:

| Return | Meaning |
|---|---|
| `{:ok, name, value}` | This child wins. Use the (possibly coerced) value. |
| `{:error, name, reason}` | This child loses. Try the next. |

## Descent semantics

A `conditional_field` does **not** drill into the value — the same value is
fed to each candidate. To descend through a list, use `structs: true` on the
inner conditional with `is_list_data`. To drill into a sub-map, use a child
`struct:` reference whose `validator:` filters maps.

## `priority: true`

At most one child may be marked `priority: true`. If that child matches, the
runtime stops and ignores siblings.

## Aggregated error shape

When no child matches, the parent emits one error map of action `:conditionals`:

```elixir
[
  %{
    field: :actor,
    action: :conditionals,
    errors: [
      %{field: :actor, action: :validator, __hint__: "actor-map", message: "It is not map"},
      %{field: :actor, action: :validator, __hint__: "actor-list", message: "It is not list"},
      %{field: :actor, action: :validator, __hint__: "actor-url", message: "It is not string"}
    ]
  }
]
```

Inner conditionals nest the same shape recursively. Use `hint: "label"` on each
child to disambiguate which arm produced which inner error.

## Arbitrary depth

Nested `conditional_field` works to any depth (closes #7, #8, #25). The runtime
recurses through the same dispatcher; each level adds one layer of `:conditionals`
aggregation to the error tree.

## Common gotchas

* If every nested conditional gates entry with `is_map_data` but the deepest
  child needs an integer, **no input can ever reach it** — the same value flows
  through each level. Use `structs: true` to iterate a list, or remove the
  gate, or restructure with sub_field.
* Mixed atom and string keys on the input are normalized by the runtime;
  validators see atom keys.
