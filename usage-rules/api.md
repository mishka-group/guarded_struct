# Runtime API — `Builder`, `Validate`, `Diff`, `Info`

Public helpers around the generated module. All accept a guarded module as
their first argument; none take the struct itself.

## `Module.builder/1,2` — full validation + struct build

```elixir
MyApp.User.builder(%{email: "..."})                 # → {:ok, %User{}} | {:error, [...]}
MyApp.User.builder(%{email: "..."}, :error)         # raise on error (if section had `error: true`)
MyApp.User.builder({:headers, attrs})               # context tuple (key, attrs)
MyApp.User.builder({:headers, attrs, :edit})        # context tuple with :add (default) | :edit
                                                     # :edit skips auto-fill on fields already populated
```

Returns `{:ok, struct}` or `{:error, [error_map]}`. See `guarded_struct:errors`.

## `GuardedStruct.Validate` — partial / standalone

```elixir
GuardedStruct.Validate.run("validate(email_r)", "alice@x.io")
# => {:ok, "alice@x.io"}

GuardedStruct.Validate.field(MyApp.User, :email, "bad")
# => {:error, [%{field: :email, action: :email_r, ...}]}

GuardedStruct.Validate.partial(MyApp.User, %{nickname: "ok"})
# → run the pipeline against just the keys present; skip enforce-key checks.
```

## `GuardedStruct.Info` — introspection

| Function | Result |
|---|---|
| `Info.describe(mod)` | One-shot map: `module`, `keys`, `enforce_keys`, `conditional_keys`, `fields`, `options`. |
| `Info.fields(mod)` | All field metadata, ordered. |
| `Info.fields_meta(mod)` | Alias for `mod.__fields__()`. |
| `Info.field(mod, name)` | O(1) lookup via `__field_meta__/1`. |
| `Info.field?(mod, name)` | Existence check. |
| `Info.field_kind(mod, name)` | `:field` / `:sub_field` / `:conditional_field` / `:virtual_field` / `:dynamic_field` / `:pattern_field`. |
| `Info.field_default(mod, name)` | Default value (unquoted). |
| `Info.field_derives(mod, name)` | Original derive string. |
| `Info.field_validator(mod, name)` | `{Mod, :fn}` tuple or `nil`. |
| `Info.field_auto(mod, name)` | Auto MFA. |
| `Info.enforce?(mod, name)` | Per-field enforce flag. |
| `Info.virtual?(mod, name)` / `Info.dynamic?(mod, name)` | Kind shortcuts. |
| `Info.sub_fields(mod)` / `virtual_fields/1` / `dynamic_fields/1` / `conditional_fields/1` | Names by kind. |
| `Info.conditional_keys(mod)` | Conditional-parent names. |
| `Info.pattern_keyed?(mod)` | Module uses regex `field` names. |
| `Info.sub_module(mod, name)` | Concat-derived submodule atom. |
| `Info.conditional_children(mod, name)` | Child metadata list. |
| `Info.enforce?/1`, `opaque?/1`, `authorized_fields?/1`, `json?/1`, `error?/1` | Section-option shorthands. |

For Ash resources, use `GuardedStruct.AshResource.Info` — same surface,
namespaced helpers that read `__guarded_*` accessors.

## `GuardedStruct.Diff` — audit-log-friendly struct diffing

```elixir
GuardedStruct.Diff.diff(a, b)            # → %{key => {old, new}}
GuardedStruct.Diff.apply(a, diff)        # → b
GuardedStruct.Diff.equal?(a, b)          # → boolean
```

Mixed-type inputs return `:not_comparable`.

## `example/0` on every generated module

Returns a struct populated from declared defaults plus type-based placeholders.
Useful for REPL exploration and seed fixtures.

```elixir
iex> MyApp.User.example()
%MyApp.User{email: nil, profile: %MyApp.User.Profile{bio: nil}}
```

## Telemetry

Every top-level `builder/1` emits via `:telemetry.execute/3`:

* `[:guarded_struct, :builder, :start]` — `%{system_time: ts}` + `%{module: mod}`
* `[:guarded_struct, :builder, :stop]` — `%{duration: ns}` + result metadata
* `[:guarded_struct, :builder, :exception]` — `%{duration: ns}` + `%{kind, reason, stacktrace}`

Attach a handler in `application.ex` for logging / metrics; the lib emits no
events otherwise.
