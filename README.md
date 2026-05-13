# GuardedStruct

<a href="https://www.buymeacoffee.com/mishkagroup" target="_blank">
  <img src="https://img.buymeacoffee.com/button-api/?text=Buy us coffee&emoji=☕&slug=mishkagroup&button_colour=FFDD00&font_colour=000000&font_family=Cookie&outline_colour=000000&coffee_colour=ffffff" alt="Buy Me A Coffee" height="50" width="210">
</a>

Build Elixir structs with validation, sanitization, nested sub-structs, conditional fields, pattern-keyed maps, and an Ash extension. Built on [Spark](https://hex.pm/packages/spark).

## What does it look like

```elixir
defmodule User do
  use GuardedStruct

  guardedstruct do
    field :name, String.t(), enforce: true,
      derives: "sanitize(trim, capitalize) validate(string, max_len=80)"

    field :email, String.t(), enforce: true,
      derives: "sanitize(trim, downcase) validate(email_r)"

    field :age, integer(),
      derives: "validate(integer, min_len=0, max_len=120)"

    field :role, String.t(), default: "user",
      derives: "validate(enum=String[admin::user::guest])"
  end
end

User.builder(%{
  name: "  alice  ",
  email: "ALICE@EXAMPLE.COM",
  age: 30
})
# => {:ok, %User{
#      name: "Alice",
#      email: "alice@example.com",
#      age: 30,
#      role: "user"
#    }}

User.builder(%{name: "x", email: "bad", age: -5})
# => {:error, [
#      %{field: :name, action: :min_len, ...},
#      %{field: :email, action: :email_r, ...},
#      %{field: :age, action: :min_len, ...}
#    ]}
```

## Installation

```elixir
def deps do
  [
    {:guarded_struct, "~> 0.1.0"}
  ]
end
```

Upgrading from `0.0.x`? See [`MIGRATION.md`](./MIGRATION.md). Existing code keeps working — `0.1.0` is fully backward-compatible.

## Why GuardedStruct

- **Compile-time DSL** with editor autocomplete, courtesy of Spark
- **Tiny runtime hot path** — derive op-strings, core-key paths, and domain patterns are all parsed once at compile time
- **Sanitize + validate together** in one expressive `derives:` op-string mini-language
- **Nested structs** with `sub_field`, plus `conditional_field` for sum-type-like dispatch (any depth)
- **Pattern-keyed maps** (regex `field` names) for free-form keys with uniform validation
- **i18n** for every error message via `GuardedStruct.Messages`
- **Ash extension** to use the same DSL inside an `Ash.Resource`
- **Atom-attack safe** by default (regex field keys stay as strings)

## Core features

### `field/2,3` — declare a field

```elixir
field :name, String.t()                                       # nullable
field :name, String.t(), enforce: true                        # required
field :name, String.t(), default: "untitled"                  # default value
field :name, String.t(), derives: "validate(string, max_len=80)"
field :name, String.t(), validator: {MyApp.Validators, :name_validator}
field :user, User.t(), struct: User                           # nested struct
field :tags, list(Tag.t()), structs: Tag                      # list of structs
```

Available options: `enforce`, `default`, `derive`, `validator`, `auto`, `from`, `on`, `domain`, `struct`, `structs`, `hint`, `priority`.

### `sub_field/2,3,4` — nested struct

```elixir
defmodule User do
  use GuardedStruct

  guardedstruct do
    field :name, String.t(), enforce: true

    sub_field :auth, struct(), enforce: true do
      field :email, String.t(), enforce: true, derives: "validate(email_r)"
      field :role, String.t(), derives: "validate(enum=String[admin::user::guest])"
    end
  end
end

User.builder(%{
  name: "Alice",
  auth: %{email: "alice@example.com", role: "admin"}
})
# => {:ok, %User{
#      name: "Alice",
#      auth: %User.Auth{email: "alice@example.com", role: "admin"}
#    }}
```

The compiler creates `%User.Auth{}` automatically.

### `conditional_field/2,3,4` — discriminated union

```elixir
guardedstruct do
  conditional_field :address, any() do
    field :address, String.t(), validator: {MyApp.Validators, :is_string_data}

    sub_field :address, struct(), validator: {MyApp.Validators, :is_map_data} do
      field :street, String.t(), enforce: true
      field :city, String.t(), enforce: true
    end
  end
end
```

Each child is tried in order; the first whose validator returns `:ok` wins. Nests to arbitrary depth.

### `virtual_field/2,3` — input-only

Validated through the full pipeline but excluded from the generated `defstruct`. Useful for cross-field validation:

```elixir
guardedstruct do
  field :password, String.t(), enforce: true, derives: "validate(string, min_len=8)"
  virtual_field :password_confirm, String.t()
end

def main_validator(attrs) do
  if attrs[:password] == attrs[:password_confirm],
    do: {:ok, attrs},
    else: {:error, [%{field: :password_confirm, action: :match, message: "..."}]}
end
```

### Pattern-keyed maps — `field` with a regex name

For free-form keys with uniform validation. Returns a plain map (no struct, since Elixir struct keys are fixed):

```elixir
defmodule Headers do
  use GuardedStruct
  guardedstruct do
    field ~r/^X-[A-Z][A-Za-z\-]*$/, String.t(),
      derives: "validate(string, max_len=500)"
  end
end

Headers.builder(%{
  "X-API-Key" => "secret",
  "X-Tenant-Id" => "abc-123"
})
# => {:ok, %{"X-API-Key" => "secret", "X-Tenant-Id" => "abc-123"}}
```

Pair with `struct:` for typed values:

```elixir
defmodule ShardsMap do
  use GuardedStruct
  guardedstruct do
    field ~r/^shard_\d+$/, struct(), struct: Shard,
      derives: "validate(map, not_empty)"
  end
end
```

Mixing atom-keyed and regex-keyed fields in the same `guardedstruct` raises `Spark.Error.DslError` at compile time. Keys stay as strings — no atom conversion, atom-table-exhaustion safe by default.

## Derive op-strings

A `derives:` string declares one or two op groups: `sanitize(...)` (transforms the input) and `validate(...)` (gates it). Comma-separated op atoms are run in order.

```elixir
"sanitize(trim, downcase) validate(string, max_len=80, email_r)"
```

### Built-in sanitize ops (11)

`trim`, `upcase`, `downcase`, `capitalize`, `basic_html`, `html5`, `markdown_html`, `strip_tags`, `tag=<sub_op>`, `string_float`, `string_integer`.

### Built-in validate ops (50+)

| Category | Ops |
|---|---|
| Type guards | `string`, `integer`, `list`, `atom`, `bitstring`, `boolean`, `exception`, `float`, `function`, `map`, `nil_value`, `not_nil_value`, `number`, `pid`, `port`, `reference`, `struct`, `tuple` |
| Emptiness | `not_empty`, `not_flatten_empty`, `not_flatten_empty_item`, `queue` |
| Length | `max_len=N`, `min_len=N` |
| Network | `url`, `tell`, `geo_url`, `email`, `email_r`, `location`, `ipv4` |
| Format | `string_boolean`, `datetime`, `range`, `date`, `regex='...'`, `not_empty_string`, `uuid`, `username`, `full_name` |
| Enums | `enum=String[a::b::c]`, `enum=Atom[...]`, `enum=Integer[...]`, `enum=Float[...]`, `enum=Map[...]`, `enum=Tuple[...]` |
| Equality | `equal=String::foo`, `equal=Integer::42`, etc. |
| Custom | `custom=[Mod, fun]` |
| Either | `either=[op1, op2, ...]` (passes if any sub-op passes) |
| Conversion | `string_float`, `string_integer`, `some_string_float`, `some_string_integer` |
| Erlang Records | `record`, `record=tag_atom` |

### Custom validators / sanitizers

Two ways: app-env plug-in (legacy) or Spark-native DSL (recommended).

**Spark-native (recommended):**

```elixir
defmodule MyApp.Derives do
  use GuardedStruct.Derive.Extension

  validator :slug, fn input ->
    is_binary(input) and Regex.match?(~r/^[a-z0-9-]+$/, input)
  end

  sanitizer :slugify, fn input when is_binary(input) ->
    input |> String.downcase() |> String.replace(~r/[^a-z0-9-]+/u, "-")
  end
end

# config/config.exs
config :guarded_struct, derive_extensions: [MyApp.Derives]

# Then use the new ops anywhere:
field :slug, String.t(), derives: "sanitize(slugify) validate(slug)"
```

**App-env plug-in (legacy, still works):**

```elixir
Application.put_env(:guarded_struct, :validate_derive, [MyApp.MyValidator])

defmodule MyApp.MyValidator do
  def validate(:my_op, input, field) do
    # ... return input or {:error, field, :my_op, "msg"}
  end
end
```

## Core keys

The four core keys (`auto`, `from`, `on`, `domain`) cross-link fields:

```elixir
guardedstruct do
  field :id, String.t(), auto: {Ecto.UUID, :generate}
  field :user_id, String.t(), auto: {Ecto.UUID, :generate}
  field :name, String.t(), enforce: true
  field :email, String.t(), enforce: true,
    domain: "?role=Equal[String::admin]"   # if role is admin, email must equal "admin"...
  field :role, String.t(), default: "user"
  field :owner_id, String.t(),
    on: "root::user_id",                   # owner_id requires user_id present
    from: "root::user_id"                  # if owner_id missing, copy from user_id
end
```

| Key | Behaviour |
|---|---|
| `auto: {Mod, :fn}` | If field is missing in `:add` mode, generate the value via the MFA |
| `auto: {Mod, :fn, default}` | Same, with a static fallback if the MFA returns nil |
| `from: "root::path"` or `"sibling::path"` | Copy a value from another path if this field is missing |
| `on: "root::path"` | If this field is provided, the dependency path must also be present |
| `domain: "!path=Type[...]"` or `"?path=Type[...]"` | Cross-field shape constraints; `!` is required, `?` is optional |

`domain` patterns support `Type[...]` (enum), `Equal[Type::value]`, `Either[op1, op2]`, `Custom[Mod, fn]`, `Tuple[...]`, `Map[...]`. All are pre-evaluated at compile time.

## Standalone validation — `GuardedStruct.Validate`

Use a schema without going through `builder/1`:

```elixir
# Tier 1 — ad-hoc op-string against a value
GuardedStruct.Validate.run("validate(string, max_len=80, email_r)", "alice@example.com")
# => {:ok, "alice@example.com"}

# Tier 2 — single field of a module
GuardedStruct.Validate.field(User, :email, "alice@x.com")
GuardedStruct.Validate.field(User, :owner_id, "u-123",
  context: %{user_id: "u-123"}    # cross-field deps from context
)
GuardedStruct.Validate.field(User, :owner_id, "u-123", mode: :isolated)
# skips on:/domain: deps entirely

# Tier 3 — partial subset (e.g. PATCH endpoints, form-as-you-type)
GuardedStruct.Validate.partial(User, %{name: "Alice", email: "alice@x.com"})
# missing fields skipped; no enforce_keys check
```

## Ash integration

```elixir
defmodule MyApp.Resources.User do
  use Ash.Resource, extensions: [GuardedStruct.AshResource]

  guardedstruct do
    field :name, String.t(), enforce: true,
      derives: "sanitize(trim) validate(string, max_len=80)"
    field :email, String.t(), enforce: true, derives: "validate(email_r)"
  end

  # ... your Ash actions, attributes, etc.
end

# The validation pipeline lives under the __guarded_*__ namespace so it
# doesn't clash with Ash's own callbacks:
MyApp.Resources.User.__guarded_validate__(%{name: "Alice", email: "alice@x.com"})
# => {:ok, %{name: "Alice", email: "alice@x.com"}}
```

## Errors as Splode exceptions (opt-in)

`builder/1` returns the legacy `{:error, [%{field, action, message}]}` tuple shape by default. Wrap with [Splode](https://hex.pm/packages/splode) for `traverse_errors/2`, `to_class/1`, JSON serialisation:

```elixir
case MyStruct.builder(input) do
  {:ok, _} = ok -> ok
  {:error, errs} -> {:error, GuardedStruct.Errors.from_tuple(errs)}
end
```

## Internationalisation

Override messages by implementing the `GuardedStruct.Messages` behaviour:

```elixir
defmodule MyApp.GuardedStructMessages do
  use GuardedStruct.Messages

  def required_fields(), do: "Lütfen gerekli alanları girin."
  def email(field), do: "#{field} geçerli bir e-posta adresi olmalıdır."
  # ... override any of the 60+ callbacks
end

# config/config.exs
config :guarded_struct, message_backend: MyApp.GuardedStructMessages
```

Defaults to English. Every error site in both the orchestration and derive layers uses `translated_message/1,2` under the hood.

## Documentation

- [Migration guide](./MIGRATION.md) — `0.0.x` → `0.1.0`
- [Changelog](./CHANGELOG.md)
- [LiveBook walkthrough](https://github.com/mishka-group/guarded_struct/blob/master/guidance/guarded-struct.livemd) — interactive examples
- DSL reference (in hexdocs) — `documentation/dsls/`
- [Blog post](https://mishka.tools/blog/guardedstruct-advanced-elixir-struct-data-validation-and-sanitization) — original motivation and design

The full docs are at [hexdocs.pm/guarded_struct](https://hexdocs.pm/guarded_struct).

## Donate

You can support this project through the "[Sponsor](https://github.com/sponsors/mishka-group)" button on GitHub or via cryptocurrency donations.

| **BTC**                                                                                                                            | **ETH**                                                                                                                            | **DOGE**                                                                                                                           | **TRX**                                                                                                                            |
| ---------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| <img src="https://mishka.tools/images/donate/BTC.png" width="200"> | <img src="https://mishka.tools/images/donate/ETH.png" width="200"> | <img src="https://mishka.tools/images/donate/DOGE.png" width="200"> | <img src="https://mishka.tools/images/donate/TRX.png" width="200"> |

<details>
  <summary>Donate addresses</summary>

**BTC**:‌

```
bc1q24pmrpn8v9dddgpg3vw9nld6hl9n5dkw5zkf2c
```

**ETH**:

```
0xD99feB9db83245dE8B9D23052aa8e62feedE764D
```

**DOGE**:

```
DGGT5PfoQsbz3H77sdJ1msfqzfV63Q3nyH
```

**TRX**:

```
TBamHas3wAxSEvtBcWKuT3zphckZo88puz
```

</details>
