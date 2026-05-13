# Migrating from `0.0.x` to `0.1.0`

**TL;DR — your existing code keeps working.** `0.1.0` rewrites the macro core on Spark, but every `0.0.x` public API is preserved. Bump the version in `mix.exs`, run `mix deps.get`, and your tests should still pass.

This guide covers what's new, what's been deprecated (nothing forced), and a few sharp edges to be aware of.

## What's unchanged

- `use GuardedStruct`
- `guardedstruct opts do … end`
- `field/2,3`, `sub_field/2,3,4`, `conditional_field/2,3,4`
- All field options: `enforce`, `default`, `derive`, `validator`, `auto`, `from`, `on`, `domain`, `struct`, `structs`, `hint`, `priority`
- All section options: `enforce`, `opaque`, `module`, `error`, `authorized_fields`, `main_validator`, `validate_derive`, `sanitize_derive`
- All 50+ validate ops and 11 sanitize ops in derive strings
- `MyStruct.builder/1,2`, `MyStruct.builder({:root, attrs})`, `MyStruct.builder({key, attrs, :add | :edit})`
- `MyStruct.keys/0,1` and `MyStruct.enforce_keys/0,1`
- `MyStruct.__information__/0`
- The `Application.put_env(:guarded_struct, :validate_derive, [...])` and `:sanitize_derive` plug-in mechanism
- `GuardedStruct.Messages` i18n behaviour and overridable callbacks

If your code only used the documented public API, **no changes are needed**.

## What's new (and worth opting into)

### 1. Pattern-keyed maps

A `field` whose name is a regex declares a map shape with no fixed keys:

```elixir
defmodule Headers do
  use GuardedStruct
  guardedstruct do
    field ~r/^X-[A-Z][A-Za-z\-]*$/, String.t(), derives: "validate(string, max_len=500)"
  end
end

Headers.builder(%{"X-API-Key" => "secret", "X-Tenant-Id" => "abc"})
# {:ok, %{"X-API-Key" => "secret", "X-Tenant-Id" => "abc"}}
```

Returns a plain map (no struct generated). Keys stay as strings — no atom conversion, atom-table-exhaustion safe.

### 2. `virtual_field`

Validated through the full pipeline but excluded from `defstruct`:

```elixir
guardedstruct do
  field :password, String.t(), enforce: true
  virtual_field :password_confirm, String.t()
end

def main_validator(attrs) do
  if attrs[:password] == attrs[:password_confirm],
    do: {:ok, attrs},
    else: {:error, [%{field: :password_confirm, action: :match, message: "..."}]}
end
```

The validated `password_confirm` value is visible to `main_validator/1` then dropped before the struct is built.

### 3. `dynamic_field`

Shorthand for a free-form map field:

```elixir
guardedstruct do
  field :name, String.t()
  dynamic_field :metadata    # type: map(), default: %{}, derives: "validate(map)"
end
```

**Security note**: `dynamic_field` values are **identity-preserved** — whatever map you submit is exactly what you get back. No string-to-atom conversion of keys at any depth, to prevent atom-table-exhaustion DoS. Read these values with string keys. See the "Atom-attack safety" section of the `GuardedStruct` module @moduledoc for full details.

### 4. `GuardedStruct.Validate` — schema-without-builder

Three-tier API:

```elixir
# Ad-hoc op-string against a value
GuardedStruct.Validate.run("validate(string, max_len=80, email_r)", "alice@x.com")

# One named field of a module
GuardedStruct.Validate.field(MyStruct, :email, "alice@x.com")
GuardedStruct.Validate.field(MyStruct, :parent_email, "p@x.com",
  context: %{account_type: "personal"}    # cross-field deps from context
)
GuardedStruct.Validate.field(MyStruct, :email, "x", mode: :isolated)

# Subset of fields (e.g. PATCH endpoints, form-as-you-type)
GuardedStruct.Validate.partial(MyStruct, %{name: "Alice", email: "alice@x.com"})
# missing fields skipped — no enforce_keys check
```

### 5. Erlang Records

```elixir
field :user_record, :tuple, derives: "validate(record)"        # any tagged tuple
field :user_record, :tuple, derives: "validate(record=user)"   # specific tag
```

### 6. Custom validators / sanitizers via Spark-native DSL

If you'd been using `Application.put_env(:guarded_struct, :validate_derive, MyMod)` with a hand-rolled `validate/3` callback, you can now write:

```elixir
defmodule MyApp.Derives do
  use GuardedStruct.Derive.Extension

  validator :slug, fn input ->
    is_binary(input) and Regex.match?(~r/^[a-z0-9-]+$/, input)
  end

  sanitizer :slugify, fn input -> ... end
end

# config/config.exs
config :guarded_struct, derive_extensions: [MyApp.Derives]
```

The legacy `Application.put_env` mechanism still works — both can coexist.

### 7. Ash extension

```elixir
use Ash.Resource, extensions: [GuardedStruct.AshResource]

guardedstruct do
  field :name, :string, enforce: true, derives: "validate(string)"
end

changes do
  change GuardedStruct.AshResource.Change   # wire into create/update
end
```

Generates `__guarded_change__/1`, `__guarded_information__/0`, `__guarded_fields__/0` under the `__guarded_*` namespace (no clash with Ash's own callbacks). The companion `GuardedStruct.AshResource.Change` module bridges the pipeline into Ash's changeset flow.

Prefer zero wiring? Set `auto_wire true` at the top of the `guardedstruct` block and the change is injected for you. See OPTIONS §15.

### 8. Splode error wrapping (opt-in)

```elixir
case MyStruct.builder(input) do
  {:error, errs} -> {:error, GuardedStruct.Errors.from_tuple(errs)}
  ok -> ok
end
```

Gives you `Splode.traverse_errors/2`, `set_path/2`, JSON serialisation. The `builder/1` return shape still defaults to the legacy `{:error, [%{field, action, message}]}` tuple — wrapping is opt-in.

## Soft deprecations

### `derive:` option renamed to `derives:`

The canonical option name is now plural — `derives:` — aligning with the
`@derives` decorator. The legacy `derive:` still works but emits a
compile-time deprecation warning. Bulk-rename in your project with:

```sh
# macOS:
grep -rl 'derive: "' lib test | xargs sed -i '' 's/\bderive: "/derives: "/g'

# Linux:
grep -rl 'derive: "' lib test | xargs sed -i 's/\bderive: "/derives: "/g'
```

When both are set on one field, `derives:` wins silently and the
deprecation warning does not fire.

## Sharp edges to watch for

### Compile-time errors for things that previously failed silently

`0.0.x`'s `Parser.parser/1` had a `rescue _ -> nil` that swallowed parse errors and produced no validation. `0.1.0` parses derives at compile time and surfaces malformed strings as `Spark.Error.DslError` at the user's source line.

Two cases where you'll see new errors:

- **Malformed `derives:` strings** that previously silently became no-ops will now raise. If you've been relying on a typo'd derive being silently ignored, fix the string.
- **`derives:` on a non-string** value (e.g. a transformer-produced atom) now raises `Spark.Error.DslError` at compile time.

If you want to keep the silent-failure behaviour for a specific case, leave the entire `derives:` option off the field.

### Mixing atom-keyed and regex-keyed `field`s in one `guardedstruct`

Compile-time error. The fix: extract the regex part into its own module and reference it via `struct:`:

```elixir
# Before (won't compile):
guardedstruct do
  field :name, String.t()
  field ~r/^tag_/, String.t()      # ⛔
end

# After:
defmodule Tags do
  use GuardedStruct
  guardedstruct do
    field ~r/^tag_/, String.t()
  end
end

defmodule User do
  use GuardedStruct
  guardedstruct do
    field :name, String.t()
    field :tags, struct(), struct: Tags
  end
end
```

### `__information__()` shape

Same keys as before, but `conditional_keys` is now populated (was always `[]` in pre-0.1.0 transitional builds — never released). If you have introspection code that depended on `conditional_keys: []`, update it.

### `MyStruct.Error.message/1` format

Now uses `translated_message(:message_exception)` and matches master's exact format:

```
{prefix from i18n callback}
 Term: {inspect(term)}
 Errors: {inspect(errors)}
```

If you were parsing the message string (rare), update your parser.

### `Application.put_env(:guarded_struct, :validate_derive, …)` interaction with strict mode

Strict op-name verification is automatically **disabled** when an Application-env plug-in is registered, since the verifier can't introspect the plug-in's op names at compile time. To get strict checking, migrate the plug-in to the Spark-native `GuardedStruct.Derive.Extension` DSL.

## How to upgrade

```elixir
# mix.exs
defp deps do
  [
    {:guarded_struct, "~> 0.1.0"},
    # All your other deps...
  ]
end
```

```sh
mix deps.get
mix compile
mix test
```

If `mix test` is green, you're done. If something fails, the most likely cause is a `derives:` string that was previously silently broken — check the compile-time error message; it'll point at the offending field.

## Anything I've missed?

If your `0.0.x` code stops working in `0.1.0` and the failure isn't covered above, please [open an issue](https://github.com/mishka-group/guarded_struct/issues) — that's a bug, not an intended migration step.
