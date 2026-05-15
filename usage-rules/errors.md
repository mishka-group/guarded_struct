# Errors — canonical shape and Splode wrapping

Every error return from this library is `{:error, list_of_error_maps}`. Each
map has one of two shapes — never anything else.

## Canonical error map

```elixir
%{
  field: atom(),                # always present; :__root__ for non-field errors
  action: atom(),               # which check produced the error
  message: String.t(),          # human-readable
  errors: [error_map()] | nil   # only on :conditionals aggregators
  # __hint__: String.t()        # present when the entity carried a `hint:` option
}
```

Examples:

```elixir
%{field: :email,    action: :email_r,         message: "..."}
%{field: :username, action: :required_fields, message: "Please submit required fields."}
%{field: :role_id,  action: :authorized_fields, message: "Unauthorized keys are present in the sent data."}
%{field: :__root__, action: :bad_parameters,  message: "..."}
%{field: :actor,    action: :conditionals,    errors: [...]}      # nested
```

### Multi-field errors

`:required_fields` and `:authorized_fields` emit **one entry per affected
field** (not one map with a `fields:` list). Filter by `action` to collect:

```elixir
errs
|> Enum.filter(&match?(%{action: :required_fields}, &1))
|> Enum.map(& &1.field)
```

## Splode wrapping (opt-in)

`GuardedStruct.Errors.from_tuple/1` converts the error list into a Splode
`Ash.Error`-style class for systems that want exception objects rather than
tuples.

```elixir
case MyApp.User.builder(input) do
  {:ok, user} -> user
  {:error, errs} ->
    GuardedStruct.Errors.from_tuple({:error, errs})  # Splode.Error class
end
```

Implementations:

* `GuardedStruct.Errors.Validation` — wraps per-field errors.
* `GuardedStruct.Errors.Unknown` — fallback for anything else.
* `GuardedStruct.Errors.Invalid` — class container.

Each child error becomes a `%GuardedStruct.Errors.Validation{}` struct with
`field`, `action`, `message`, `hint`, and `vars` fields. `:conditionals`
aggregators preserve their `child_errors` recursively.

## Section `error: true`

Setting `error: true` on the section (or on a `sub_field`) generates a
`Module.Error` exception:

```elixir
guardedstruct error: true do
  field :email, :string, enforce: true
end

MyApp.User.builder(%{}, true)
# ** (MyApp.User.Error) ...
```

`builder/2`'s second argument toggles raise-mode. Without `error: true`,
`builder/2` ignores the flag and still returns `{:error, list}`.

## Compile-time errors

Spark verifiers and the derive parser surface as `Spark.Error.DslError`
with `path:` (DSL location) and `module:` (caller) — these never reach
runtime. Triggers:

* Malformed `derives:` string.
* Unknown sanitize/validate op (and not declared in any registered extension).
* `validator: {Mod, :fn}` not exported.
* `auto: {Mod, :fn}` not exported.
* `struct: AnotherMod` cycle.
