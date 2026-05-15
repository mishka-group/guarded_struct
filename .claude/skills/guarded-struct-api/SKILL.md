---
name: guarded-struct-api
description: Use when calling the runtime helpers around a guarded module — `Module.builder/1,2`, `GuardedStruct.Validate.{run,field,partial}`, `GuardedStruct.Diff.{diff,apply,equal?}`, `GuardedStruct.Info.*` introspection, telemetry events at `[:guarded_struct, :builder, _]`, or `GuardedStruct.Errors.from_tuple/1`. Covers the canonical error shape consumers must handle.
---

# Runtime API + introspection

Reference: `usage-rules/api.md` and `usage-rules/errors.md`.

## `Module.builder/1,2`

```elixir
MyApp.User.builder(%{email: "a@b.io"})           # → {:ok, %User{}} | {:error, [error_map]}
MyApp.User.builder(%{email: "a@b.io"}, true)     # raise the module's Error exception (if `error: true`)
MyApp.User.builder({:headers, attrs})            # context tuple (key, attrs)
MyApp.User.builder({:headers, attrs, :edit})     # 3-tuple with :add (default) | :edit
                                                  # :edit skips auto-fill on fields already populated
```

The `{:error, list}` second element is **always a list**. Each error map:
`%{field: atom, action: atom, message: String, [errors: [...]]}`.

## `GuardedStruct.Validate`

```elixir
GuardedStruct.Validate.run("validate(email_r)", "alice@x.io")
# {:ok, "alice@x.io"} | {:error, [error_map]}

GuardedStruct.Validate.field(MyApp.User, :email, "bad")
# {:ok, _} | {:error, [error_map]}

GuardedStruct.Validate.partial(MyApp.User, %{nickname: "ok"})
# Validates only keys present. Skips enforce-key checks.
```

## `GuardedStruct.Info`

Compile-time-baked introspection. All functions take the module atom.

```elixir
GuardedStruct.Info.describe(MyApp.User)         # one-shot summary map
GuardedStruct.Info.fields(MyApp.User)           # list of field metadata
GuardedStruct.Info.field(MyApp.User, :email)    # O(1) by name
GuardedStruct.Info.field_kind(MyApp.User, :email)   # :field | :sub_field | ...
GuardedStruct.Info.enforce?(MyApp.User, :email)
GuardedStruct.Info.sub_fields(MyApp.User)       # names only
GuardedStruct.Info.conditional_keys(MyApp.User)
GuardedStruct.Info.sub_module(MyApp.User, :profile)  # → MyApp.User.Profile
GuardedStruct.Info.enforce?/1, opaque?/1, authorized_fields?/1, json?/1, error?/1
```

For Ash resources, use `GuardedStruct.AshResource.Info` — same surface.

## `GuardedStruct.Diff`

```elixir
GuardedStruct.Diff.diff(a, b)         # %{key => {old, new}} | :not_comparable
GuardedStruct.Diff.apply(a, diff)     # → b
GuardedStruct.Diff.equal?(a, b)       # boolean
```

## Telemetry

Every `Module.builder/1` call emits:

* `[:guarded_struct, :builder, :start]` — measurements `%{system_time: ts}`, metadata `%{module: mod}`
* `[:guarded_struct, :builder, :stop]` — `%{duration: ns}` + `%{result: :ok | :error, error_count: n, module: mod}`
* `[:guarded_struct, :builder, :exception]` — `%{duration: ns}` + `%{kind, reason, stacktrace, module: mod}`

Attach handlers in `application.ex`. No other events emitted.

## `GuardedStruct.Errors` — Splode wrapping (opt-in)

```elixir
GuardedStruct.Errors.from_tuple({:error, errs})
# %Ash.Error{} class containing %GuardedStruct.Errors.Validation{} items
```

Each error map becomes a `Validation` struct with `field`, `action`, `message`,
`hint`, `vars`, and (for `:conditionals`) `child_errors`. Unknown shapes fall
through to `GuardedStruct.Errors.Unknown`.

## Consumer pattern

```elixir
case MyApp.User.builder(input) do
  {:ok, user} ->
    handle_user(user)

  {:error, errs} ->
    # errs is always a list. Each item has :field, :action, :message.
    required = Enum.filter(errs, &match?(%{action: :required_fields}, &1))
    Enum.each(required, fn %{field: f} -> Logger.warn("missing: #{f}") end)
end
```

Don't `List.wrap/1` the error — it's already a list. Don't pattern-match on
`%{fields: [...]}` (plural) — that shape was removed in the canonical-shape
migration.
