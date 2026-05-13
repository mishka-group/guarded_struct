# `guarded_struct` v0.1.0 — what's new

PR [#13](https://github.com/mishka-group/guarded_struct/pull/13) — rewrite on top of [Spark](https://hex.pm/packages/spark). Closes #1, #2, #4, #5, #6, #11, #12. Public API is fully backward-compatible.

Each section: **what it is** · **one real-world example**. For deeper coverage see the corresponding fixture under `test/support/fixtures/`.

---

## 1 · Editor autocomplete in your IDE — _closes #1_

Type `field` / `sub_field` / `derives` inside a `guardedstruct` block in VSCode (with ElixirLS) or Lexical — completions appear automatically. Free via `Spark.ElixirSense.Plugin`. No setup.

---

## 2 · Single-field validation — _closes #2_

Validate one field of a schema without going through the whole `builder/1`. Perfect for live-as-you-type form validation.

```elixir
defmodule User do
  use GuardedStruct
  guardedstruct do
    field :email, String.t(), enforce: true, derives: "validate(email_r)"
    field :age,   integer(),                  derives: "validate(integer)"
  end
end

# Validate just :email — useful in a LiveView `phx-change` handler:
GuardedStruct.Validate.field(User, :email, "bad")
# => {:error, [%{field: :email, action: :email_r, message: "..."}]}

# Or validate a raw value against an op-string (no module needed):
GuardedStruct.Validate.run("validate(email_r)", "alice@x.io")
# => {:ok, "alice@x.io"}

# Or validate a subset (e.g. for PATCH endpoints):
GuardedStruct.Validate.partial(User, %{email: "alice@x.io"})
# => {:ok, %{email: "alice@x.io"}}    # :age omission ignored
```

> Fixture: `test/support/fixtures/showcase.ex` (`EnterpriseAccount`)

---

## 3 · `@derives` decorator — cleaner DSL — _part of #4_

Move long `derives:` strings off the `field` line. One-shot, consumed by the next entity.

```elixir
guardedstruct do
  @derives "sanitize(trim, downcase) validate(string, email_r, max_len=320)"
  field :email, String.t(), enforce: true

  @derives "validate(integer, min_len=18, max_len=120)"
  field :age, integer()
end
```

Also works on `sub_field`, `conditional_field`, `virtual_field`, `dynamic_field`. `@derive_rules` is a longer alias for the same thing.

> Fixtures: `decorated.ex`, `decorated_all_entities.ex`, `mixed_decorator_inline.ex`

---

## 4 · `derives:` is the canonical name (legacy `derive:` deprecated) — _part of #4_

The plural form `derives:` is now the canonical option name. `derive:` still works but emits a compile-time deprecation warning. Plural aligns with the `@derives` decorator above.

```elixir
field :email, String.t(), derives: "validate(email_r)"  # ✓ canonical
field :email, String.t(), derive:  "validate(email_r)"  # ⚠ deprecated, warns
```

---

## 5 · `virtual_field` — input-only fields — _closes #5_

For "password confirmation"-style fields: validated but **not stored** on the resulting struct. Useful with `main_validator/1` for cross-field checks.

```elixir
defmodule Signup do
  use GuardedStruct
  guardedstruct do
    field :email,    String.t(), enforce: true, derives: "validate(email_r)"
    field :password, String.t(), enforce: true, derives: "validate(string, min_len=8)"
    virtual_field :password_confirmation, String.t(), enforce: true
  end

  def main_validator(%{password: p, password_confirmation: p} = a), do: {:ok, a}
  def main_validator(_), do: {:error, [%{field: :password_confirmation, action: :match, message: "doesn't match"}]}
end

{:ok, %Signup{email: ..., password: ...}} =
  Signup.builder(%{email: "a@b.io", password: "hunter22", password_confirmation: "hunter22"})
# Note: %Signup{} doesn't have :password_confirmation — virtual fields are dropped.
```

> Fixture: `test/support/fixtures/forms.ex`

---

## 6 · Erlang Record support — _closes #6_

For Elixir code that wraps Erlang/OTP returns (Mnesia rows, `:gen_event` notifications, RPC results). Validates that a value is a tagged tuple with the right tag.

```elixir
require Record
Record.defrecord(:user, :user, name: nil, age: nil)

defmodule AuditEvent do
  use GuardedStruct
  guardedstruct do
    field :user_record, :tuple, enforce: true, derives: "validate(record=user)"
  end
end

AuditEvent.builder(%{user_record: user(name: "Alice", age: 30)})
# => {:ok, %AuditEvent{user_record: {:user, "Alice", 30}}}

AuditEvent.builder(%{user_record: {:wrong_tag, ...}})
# => {:error, [%{action: :record, ...}]}    # wrong tag rejected
```

> Fixture: `test/support/fixtures/records.ex`

---

## 7 · `dynamic_field` — open-shape map fields — _part of #11_

Shorthand for "this field is a free-form map" — user can put any keys they want. Perfect for `:metadata`, `:settings`, webhook payloads, third-party integration data.

> **Security note**: `dynamic_field` values are **identity-preserved** — whatever map you submit is exactly what you get back. No key conversion at any depth. This is intentional to prevent atom-table-exhaustion DoS from attacker-controlled keys. Read these values with **string keys** (e.g. `doc.metadata["theme"]`). See the "Atom-attack safety" section of the `GuardedStruct` module @moduledoc for full details.

```elixir
defmodule UserProfile do
  use GuardedStruct
  guardedstruct do
    field :id,    String.t(), enforce: true
    field :email, String.t(), enforce: true, derives: "validate(email_r)"

    # Open-shape — keys unknown at compile time:
    dynamic_field :preferences
    dynamic_field :integration_data, derives: "validate(map, not_empty)"
  end
end

UserProfile.builder(%{
  id: "u1", email: "a@b.io",
  preferences:      %{theme: "dark", custom_xyz_42: "anything"},
  integration_data: %{stripe_id: "cus_...", salesforce_id: "00Q..."}
})
# Each map's KEYS aren't pre-declared. dynamic_field accepts whatever shape.
```

Supports the same cross-field opts as `field`: `enforce`, `auto`, `from`, `on`, `domain`, `validator`, `derives`.

> Fixture: `test/support/fixtures/dynamic.ex` + `test/fixtures/dynamic_field_full_opts_test.exs`

---

## 8 · Pattern-keyed maps — regex `field` names — _closes #11_

Different from `dynamic_field`: the WHOLE MODULE's `builder/1` returns a typed map (no defstruct). Keys must match the regex; values validated against a referenced struct.

```elixir
defmodule Shard do
  use GuardedStruct
  guardedstruct do
    field :node, String.t(), enforce: true, derives: "validate(ipv4)"
  end
end

defmodule ShardsMap do
  use GuardedStruct
  guardedstruct do
    field ~r/^shard_\d+$/, struct(), struct: Shard
  end
end

ShardsMap.builder(%{
  "shard_1" => %{node: "10.0.0.1"},
  "shard_2" => %{node: "10.0.0.2"}
})
# => {:ok, %{"shard_1" => %Shard{...}, "shard_2" => %Shard{...}}}
#         ^ a plain MAP, not a struct

ShardsMap.builder(%{"banana" => ...})    # key doesn't match → error
```

> Fixture: `test/support/fixtures/dynamic.ex` (`ShardsMap`, `ClusterPlan`)

---

## 9 · Nested-list validation fix — _closes #12_

Sub_fields with `structs: true` (list-of-shape) inside another `structs: true` now validate each item correctly at every depth. Pre-0.1.0 silently mis-validated nested lists.

```elixir
defmodule NestedListStruct do
  use GuardedStruct
  guardedstruct do
    sub_field :list, list(struct()), structs: true, enforce: true do
      field :id, String.t(), enforce: true
      sub_field :sublist, list(struct()), structs: true, enforce: true do
        field :id, String.t(), enforce: true
      end
    end
  end
end

# Now: each nested-list item gets its own validation pass — :id required at every level.
```

---

## 10 · Nested `conditional_field` — _part of #4_

Conditional inside conditional inside conditional. Was unsupported in 0.0.x.

```elixir
defmodule Block do
  use GuardedStruct
  guardedstruct do
    conditional_field :content, any() do
      field :content, String.t(), hint: "paragraph", validator: {V, :is_string}
      sub_field :content, struct(), hint: "image", validator: {V, :is_map} do
        field :url, String.t(), enforce: true, derives: "validate(url)"
      end
      conditional_field :content, any(), structs: true, hint: "gallery", validator: {V, :is_list} do
        field :content, String.t()
        field :content, struct(), struct: Image
      end
    end
  end
end
```

> Fixture: `test/support/fixtures/conditionals.ex` (`Block`, 7-level `Document`)

---

## 11 · `json: true` — JSON encoding for API responses

Auto-derive a JSON encoder on the struct (and all sub_field submodules). Precedence: `Jason.Encoder` if `:jason` is in the user's deps, otherwise the built-in `JSON.Encoder` on Elixir 1.18+. No-op if neither is available. For Phoenix/Plug response payloads.

```elixir
defmodule Order do
  use GuardedStruct
  guardedstruct json: true do
    field :id,    String.t(), enforce: true
    field :total, integer(),  enforce: true
  end
end

{:ok, o} = Order.builder(%{id: "abc", total: 99})
Jason.encode!(o)    # => ~s({"id":"abc","total":99})
# or, on Elixir 1.18+ without Jason in deps:
JSON.encode!(o)     # => ~s({"id":"abc","total":99})
```

---

## 12 · Custom validators / sanitizers — Spark-native DSL

Define your own `validate(slug)`, `sanitize(slugify)` ops as a small extension module.

```elixir
defmodule MyApp.Derives do
  use GuardedStruct.Derive.Extension
  validator :slug, fn s -> is_binary(s) and Regex.match?(~r/^[a-z0-9-]+$/, s) end
  sanitizer :slugify, fn s -> String.downcase(s) |> String.replace(~r/[^a-z0-9]+/, "-") end
end

# Activate globally:
config :guarded_struct, derive_extensions: [MyApp.Derives]

# Or per-module:
defmodule Post do
  use GuardedStruct, derive_extensions: [MyApp.Derives]
  guardedstruct do
    field :slug, String.t(), derives: "sanitize(slugify) validate(slug)"
  end
end
```

> Fixture: `test/support/fixtures/custom_derives.ex`

---

## 13 · Splode error wrapping (opt-in)

Convert `{:error, errs}` lists into typed Splode exceptions with `traverse_errors`, `set_path`, JSON-encodable shape.

```elixir
case User.builder(input) do
  {:error, errs} -> {:error, GuardedStruct.Errors.from_tuple(errs)}
  ok -> ok
end
```

---

## 14 · `Diff` / `Info` / `example/0` helpers

```elixir
GuardedStruct.Diff.diff(user_v1, user_v2)
# => %{name: {:changed, "Alice", "Alicia"}}      # audit-log-friendly diff

GuardedStruct.Info.field?(User, :email)          # => true (compile-time introspection)
User.example()                                   # => %User{name: "", age: 0, ...} — REPL helper
```

---

## 15 · Ash resource extension

Use the GuardedStruct DSL inside `Ash.Resource` to add field-level validate/sanitize rules without re-defining `defstruct`.

```elixir
defmodule MyApp.User do
  use Ash.Resource, domain: MyApp.Domain, extensions: [GuardedStruct.AshResource]

  attributes do
    uuid_primary_key :id
    attribute :email, :string, allow_nil?: false
  end

  guardedstruct do
    field :email, :string, derives: "sanitize(trim, downcase) validate(email_r)"
  end
end

MyApp.User.__guarded_validate__(%{email: " ALICE@X.io "})
# => {:ok, %{email: "alice@x.io"}}
```

---

## 16 · Telemetry events — production observability

Every top-level `builder/1` call emits 3 events. Attach a handler to log/measure/trace.

```elixir
# In your app startup (e.g. application.ex):
:telemetry.attach("log-builds",
  [:guarded_struct, :builder, :stop],
  fn _e, %{duration: d}, %{module: m, result: r}, _ ->
    Logger.info("#{inspect(m)} #{r} in #{System.convert_time_unit(d, :native, :microsecond)}µs")
  end, nil)
```

Events: `[:guarded_struct, :builder, :start | :stop | :exception]`. APM libraries (AppSignal, Datadog, Honeycomb) auto-consume.

---

## 17 · `mix igniter.install guarded_struct`

One-command project setup:

```sh
mix igniter.install guarded_struct
# 1. Adds {:guarded_struct, "~> 0.1.0"} to mix.exs
# 2. Registers `lint` alias (mix spark.formatter + mix format)
# 3. Seeds `config :guarded_struct, derive_extensions: []`
```

---

## 18 · `mix lint` alias

Run `mix lint` after editing a guardedstruct module — it updates `.formatter.exs`'s `spark_locals_without_parens` (so the DSL keywords stay paren-free) and then runs `mix format`.

---

## App env keys

| Key | What it does |
|---|---|
| `derive_extensions: [Mod, ...]` | Globally register custom-op modules (see §12) |
| `message_backend: Mod` | i18n backend module (Gettext, Cldr, or custom) |

```elixir
config :guarded_struct,
  derive_extensions: [MyApp.Derives],
  message_backend:   MyApp.GuardedStructMessages
```

---

## Dependencies added

| Dep | Scope | Why |
|---|---|---|
| `:spark` ~> 2.7 | runtime | DSL framework |
| `:splode` ~> 0.3 | runtime | Error class hierarchy (§13) |
| `:telemetry` ~> 1.0 | runtime | Builder events (§16) |
| `:html_sanitize_ex` ~> 1.5 | runtime | for `sanitize(strip_tags, basic_html, html5)` ops |
| `:igniter` ~> 0.8 | dev/test | Installer mix task (§17) |
| `:sourceror` ~> 1.7 | dev/test | For `mix spark.formatter` |
| `:jason` ~> 1.4 | dev/test | Test coverage for `json: true` (§11) |
| `:stream_data` ~> 1.1 | dev/test | Property-based tests |

Optional deps unchanged: `email_checker`, `ex_url`, `ex_phone_number`, `sweet_xml`.

---

## Bug fixes worth flagging

- Nested-list validation (§9, closes #12)
- `__information__/0.conditional_keys` now populated (was `[]` in 0.0.x)
- All 14 `Messages` callbacks reachable again (some were dead in 0.0.x)
- Parser no longer crashes on invalid UTF-8 — caught by property-based tests
- `virtual_field`'s `derives:` now actually fires at runtime (two-pass derive in `Runtime`)
- Pre-evaluated `enum=Map[…]` / `equal=Map::…` operands at compile time — zero `Code.eval_string/1` in the runtime hot path
