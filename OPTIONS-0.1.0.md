# `guarded_struct` v0.1.0 — full options reference

Every option, module, attribute, mix task, app-env key, telemetry event,
and generated function added in `0.1.0`. Organised for review.

Each entry: **what it is** · **where it lives** · **real example**.

---

## 1 · Top-level section options — `guardedstruct opts do … end`

> Defined in `lib/guarded_struct/dsl.ex` (the `@section` schema).
> All of these go in the `opts` keyword passed to `guardedstruct`.

| Option | One-line description |
|---|---|
| `enforce: true` | Treat every field as required unless it has a `default:` |
| `opaque: true` | Emit `@opaque t()` instead of `@type t()` |
| `module: SubName` | Generate a nested module of this name (legacy parity) |
| `error: true` | Generate a `<Mod>.Error` exception per level |
| `authorized_fields: true` | Reject unknown keys in input instead of dropping them |
| `main_validator: {Mod, :fn}` | Whole-struct validator hook called after field-level |
| `validate_derive: [...]` | Auto-prepend these `validate(...)` ops to every field |
| `sanitize_derive: [...]` | Auto-prepend these `sanitize(...)` ops to every field |
| `jason: true` | **NEW** auto-emit `@derive Jason.Encoder` for the struct |

Example — `jason: true`:

```elixir
defmodule Order do
  use GuardedStruct
  guardedstruct jason: true do
    field :id,    String.t(), enforce: true
    field :total, integer(),  enforce: true
  end
end

{:ok, o} = Order.builder(%{id: "abc", total: 99})
Jason.encode!(o)   # => ~s({"id":"abc","total":99})
```

---

## 2 · Per-`field` options

> Defined in `lib/guarded_struct/dsl.ex` (the `@field` entity schema).

| Option | One-line description |
|---|---|
| `enforce: true` | Mark this single field required |
| `default: value` | Fallback value when key is absent |
| `derives: "..."` | Sanitize/validate mini-language (see §4) |
| `validator: {Mod, :fn}` | Per-field validator MFA |
| `auto: {Mod, :fn}` / `{Mod, :fn, :edit}` | Compute the value at build time |
| `from: "root::path"` | Pull value from elsewhere in the input map |
| `on: "root::path"` | Require another field/path to be present |
| `domain: "!path=Type[...]"` | Cross-field domain constraint expression |
| `struct: AnotherMod` | This field is built via another GuardedStruct |
| `structs: true` *or* `AnotherMod` | This field is a *list* of that shape |
| `hint: "label"` | Custom label propagated into conditional errors |
| `priority: true` | First-match-wins short-circuit (in `conditional_field`) |

Example — `from:` + `auto:`:

```elixir
guardedstruct do
  field :id,         String.t(), auto: {GuardedStruct.Helper.UUID, :generate}
  field :public_key, String.t(), from: "root::user::api_key"
end

User.builder(%{user: %{api_key: "ABC123"}})
# => {:ok, %User{id: "<uuid>", public_key: "ABC123"}}
```

---

## 3 · Entity types (kinds of field)

> Each defined in `lib/guarded_struct/dsl/<name>.ex` and registered in
> `lib/guarded_struct/dsl.ex`.

| Entity | What it does | File |
|---|---|---|
| `field` | Regular struct field | `dsl/field.ex` |
| `sub_field` | Nested struct, generates a submodule | `dsl/sub_field.ex` |
| `conditional_field` | First-match-wins variant resolver | `dsl/conditional_field.ex` |
| `virtual_field` | **NEW** in-pipeline field, excluded from `defstruct` | `dsl/virtual_field.ex` |
| `dynamic_field` | **NEW** runtime-extensible map field | `dsl/field.ex` (target reused) |
| `field` with a **regex name** | **NEW** pattern-keyed map field (closes #11) | `transformers/codegen.ex` (Regex branch) |

Example — `virtual_field`:

```elixir
guardedstruct do
  field :password,         String.t(), enforce: true
  field :hashed_password,  String.t(),
    auto: {MyApp.Auth, :hash, :virtual_password}

  virtual_field :virtual_password, String.t(),
    derives: "validate(string, min_len=8)"
end
```

`:virtual_password` is validated, then consumed by `auto:`, then dropped —
it never appears in `%User{}`.

Example — `dynamic_field`:

```elixir
guardedstruct do
  field :id, String.t(), enforce: true
  dynamic_field :metadata, map(),
    default: %{},
    derives: "validate(map)"
end

Doc.builder(%{id: "x", metadata: %{any: "shape", you: "want"}})
```

Keys at runtime are unrestricted (no atom-table-exhaustion DoS — keys stay
strings unless explicitly listed elsewhere).

Example — pattern-keyed map (regex `field` name):

```elixir
defmodule ShardsMap do
  use GuardedStruct
  guardedstruct do
    field ~r/^shard_\d+$/, struct(),
      struct: Shard,
      derives: "validate(map, not_empty)"
  end
end

ShardsMap.builder(%{
  "shard_1" => %{node: "10.0.0.1"},
  "shard_2" => %{node: "10.0.0.2"}
})
# => {:ok, %{"shard_1" => %Shard{...}, "shard_2" => %Shard{...}}}
```

- Returns a **plain map**, not a struct (Elixir struct keys are fixed at compile time).
- Keys stay as strings (atom-table-exhaustion safe).
- Mixing atom-keyed and regex-keyed `field`s in the same `guardedstruct`
  raises `Spark.Error.DslError` at compile time.

---

## 4 · `derives:` mini-language ops

> Op definitions: `lib/guarded_struct/derive/registry.ex`
> Runtime apply: `lib/guarded_struct/derive/validation_derive.ex` and `sanitizer_derive.ex`
> Param shapes validated at compile-time by `lib/guarded_struct/derive/op_param_validator.ex`

**Validators** — 47 ops in registry. Common: `string`, `integer`, `float`,
`boolean`, `atom`, `list`, `map`, `not_empty`, `max_len=N`, `min_len=N`,
`enum=String[a::b::c]`, `regex=^...$`, `url`, `uuid`, `email_r`, `date`,
`datetime`, `ipv4`, `username`, `equal=v`, `record=Tag`, `custom=Mod::fn`.

**Sanitizers** — 11 ops: `trim`, `upcase`, `downcase`, `capitalize`,
`basic_html`, `html5`, `markdown_html`, `strip_tags`, `tag=Atom`,
`string_float`, `string_integer`.

Example — combined:

```elixir
field :email, String.t(),
  derives: "sanitize(trim, downcase) validate(string, email_r, max_len=320)"
```

### 4a · Erlang Record support — **NEW** (closes #6)

`validate(record=Tag)` checks tagged-tuple shape (Elixir `Record.defrecord/2`
or raw Erlang records).

```elixir
require Record
Record.defrecord(:user, name: nil, age: nil)

defmodule Wrapper do
  use GuardedStruct
  guardedstruct do
    field :u, :tuple, derives: "validate(record=user)"
  end
end

Wrapper.builder(%{u: user(name: "Alice", age: 30)})
# => {:ok, %Wrapper{u: {:user, "Alice", 30}}}
```

### 4b · Compile-time op-evaluator

> File: `lib/guarded_struct/derive/op_evaluator.ex`

Pre-evaluates `enum=Map[…]` / `enum=Tuple[…]` / `equal=Map::…` operands
at compile time so there are zero `Code.eval_string` calls on the runtime
hot path.

### 4c · Derive runtime runner

> File: `lib/guarded_struct/derive/derive.ex`

The pipeline that actually applies a parsed op-list to a value. Public
entrypoint `Derive.derive/1` consumed by `builder/1`, `Validate.run/2`,
`Validate.field/4`.

---

## 4d · `derives:` vs legacy `derive:` — naming change

> Implementation: `lib/guarded_struct/transformers/parse_derive.ex` (`resolve/2`).
> Tests: `test/derives_deprecation_test.exs`.

In `0.1.0` the canonical option name is **`derives:`** (plural). The
legacy `derive:` still works but emits a compile-time deprecation
warning via `Spark.Warning.warn_deprecated/4`. The plural form aligns
with the `@derives` decorator (§5).

| Form | Status |
|---|---|
| `derives: "..."` | ✅ canonical |
| `derive: "..."` | ⚠️ soft-deprecated, will be removed in a future release |
| Both on one field | `derives:` wins, no warning |

```elixir
# new
field :email, String.t(), derives: "sanitize(trim) validate(email_r)"

# still works, but compiles with:
#   warning: `derive:` option on field :email of MyMod is deprecated.
#   Use `derives:` instead. `derive:` will be removed in a future release.
field :email, String.t(), derive: "sanitize(trim) validate(email_r)"
```

---

## 5 · `@derive_rules` / `@derives` decorator — **NEW**

> Implemented as AST walker in `lib/guarded_struct.ex` (`transform_derive_rules/1`).
> Tests: `test/derive_rules_decorator_test.exs`.

One-shot decorator that injects `derives:` into the immediately-following
field. Cleaner than inline when the rule is long. **Consumed only by the
next field-like declaration** (like `@doc`).

```elixir
guardedstruct do
  @derive_rules "validate(string, max_len=10)"
  field :name, String.t()

  @derives "validate(integer, min_len=0)"          # @derives works too
  field :age, integer()

  field :plain, String.t()                         # not decorated
end
```

If the next field already has its own `derives:` opt, the inline one wins.

---

## 6 · Standalone validation API — `GuardedStruct.Validate`

> File: `lib/guarded_struct/validate.ex`
> Tests: `test/validate_test.exs`.
> Closes issue **#2**.

| Function | One-line description |
|---|---|
| `Validate.run/2` | Apply a derive op-string to a single value, no module needed |
| `Validate.field/4` | Validate one named field of a `guardedstruct` module |
| `Validate.partial/2` | Validate a subset of fields — missing fields skipped |

Example — `Validate.run/2`:

```elixir
GuardedStruct.Validate.run("validate(string, email_r)", "x@y.io")
# => {:ok, "x@y.io"}

GuardedStruct.Validate.run("validate(string, email_r)", "nope")
# => {:error, [%{field: :__value__, action: :email_r, message: "..."}]}
```

Example — `Validate.partial/2` (PATCH-style form validation):

```elixir
GuardedStruct.Validate.partial(User, %{email: "a@b.c"})
# => {:ok, %{email: "a@b.c"}} — name omitted, no enforce error
```

---

## 7 · Diff / patch — `GuardedStruct.Diff`

> File: `lib/guarded_struct/diff.ex`
> Tests: `test/diff_test.exs`.

| Function | One-line description |
|---|---|
| `Diff.diff/2` | Field-by-field change map, recurses into sub_fields |
| `Diff.apply/2` | Apply a diff back onto a struct |
| `Diff.equal?/2` | Field-by-field equality short-circuit |

Example:

```elixir
a = %User{name: "Alice", age: 30}
b = %User{name: "Alice", age: 31}

GuardedStruct.Diff.diff(a, b)
# => %{age: {:changed, 30, 31}}

GuardedStruct.Diff.apply(a, %{age: {:changed, 30, 31}})
# => %User{name: "Alice", age: 31}
```

---

## 8 · Splode error aggregator — `GuardedStruct.Errors`

> Files:
> - `lib/guarded_struct/errors.ex` — `Splode` class root
> - `lib/guarded_struct/errors/invalid.ex` — `:invalid` class
> - `lib/guarded_struct/errors/validation.ex` — single field error
> - `lib/guarded_struct/errors/unknown.ex` — uncategorised
>
> Tests: `test/errors_test.exs`.

Opt-in wrapper that converts the raw `[%{field, action, message}, ...]`
error list into typed Splode exceptions with `traverse_errors`,
`set_path`, JSON-encodable shape.

```elixir
case User.builder(input) do
  {:error, errs} ->
    class = GuardedStruct.Errors.from_tuple(errs)
    GuardedStruct.Errors.traverse_errors(class, &Exception.message/1)
  ok ->
    ok
end

# Or construct one directly:
GuardedStruct.Errors.Validation.exception(
  field: :email,
  action: :email_r,
  message: "Invalid email format"
)
```

### Per-level generated `<MyMod>.Error` exception

When the section is given `error: true`, each level gets its own
`defexception`. Message format and i18n match the legacy 0.0.x line.

```elixir
guardedstruct error: true do
  field :name, String.t(), enforce: true
end

# => raises %MyMod.Error{...} with translated_message(:message_exception)
```

---

## 9 · Schema emitter — `GuardedStruct.Schema`

> File: `lib/guarded_struct/schema.ex`
> Tests: `test/schema_test.exs`.
> Closes issue **#3**.

| Function | One-line description |
|---|---|
| `Schema.json_schema/1` | JSON Schema 2020-12 map for a GuardedStruct module |
| `Schema.openapi/1` | **NEW** OpenAPI 3.1 `components.schemas` envelope |
| `Schema.typescript/1` | TypeScript `interface` declaration |

```elixir
GuardedStruct.Schema.json_schema(User)
# => %{"$schema" => "...", "type" => "object", "properties" => ..., "required" => [...]}

GuardedStruct.Schema.openapi([User, Order])
# => %{"openapi" => "3.1.0", "components" => %{"schemas" => %{"User" => ..., "Order" => ...}}}

GuardedStruct.Schema.typescript(User)
# => "export interface User {\n  name: string;\n  age?: number;\n}\n"
```

---

## 10 · Ash resource extension — `GuardedStruct.AshResource`

> Files:
> - `lib/guarded_struct/ash_resource.ex` — the extension
> - `lib/guarded_struct/ash_resource/info.ex` — info accessors
> - `lib/guarded_struct/transformers/generate_ash_validator.ex` — codegen
>
> Tests: `test/ash_resource_test.exs`.

Bolts the `guardedstruct do … end` block onto an Ash resource without
redefining its `defstruct` (Ash already does that). Exposes three
hooks on the resource module:

| Function | One-line description |
|---|---|
| `__guarded_validate__/1` | Run the validate pipeline on input attrs, return `{:ok, attrs} \| {:error, errs}` |
| `__guarded_information__/0` | Same metadata as standalone, separate namespace |
| `__guarded_fields__/0` | Internal field-meta list (Ash namespace) |

```elixir
defmodule MyApp.User do
  use Ash.Resource, domain: MyApp.Domain,
    extensions: [GuardedStruct.AshResource]

  attributes do
    uuid_primary_key :id
    attribute :email, :string, allow_nil?: false
  end

  guardedstruct do
    field :email, :string,
      derives: "sanitize(trim, downcase) validate(string, email_r)"
  end
end

MyApp.User.__guarded_validate__(%{email: "  ALICE@X.IO  "})
# => {:ok, %{email: "alice@x.io"}}
```

---

## 11 · Custom derive ops — `GuardedStruct.Derive.Extension`

> File: `lib/guarded_struct/derive/extension.ex`
> Tests: `test/derive_extension_test.exs`.

User-defined `validate(my_op)` / `sanitize(my_op)` ops in a small DSL.

```elixir
defmodule MyApp.Derives do
  use GuardedStruct.Derive.Extension

  validator :slug, fn s -> is_binary(s) and Regex.match?(~r/^[a-z0-9-]+$/, s) end
  sanitizer :slugify, fn s when is_binary(s) ->
    s |> String.downcase() |> String.replace(~r/[^a-z0-9-]+/u, "-")
  end
end

# config/config.exs
config :guarded_struct, derive_extensions: [MyApp.Derives]

# any module:
field :slug, String.t(), derives: "sanitize(slugify) validate(slug)"
```

---

## 12 · Transformers (compile-time pipeline)

> All under `lib/guarded_struct/transformers/`.

| Transformer | What it does |
|---|---|
| `ParseDerive` | Tokenise the `derives:` string into an op-map once at compile time |
| `VerifyDeriveOps` | **NEW** strict-mode: unknown op atoms → `DslError`, with typo suggestion |
| `ParseCoreKeys` | Split `"root::a::b"` into `[:root, :a, :b]` |
| `VerifyCoreKeyPaths` | **NEW** strict-mode: `from:`/`on:` paths must resolve to real fields |
| `ParseDomain` | Parse `"!path=Type[...]"` domain expressions |
| `GenerateSubFieldModules` | Build each `sub_field` as its own submodule with full surface |
| `GenerateBuilder` | Emit `defstruct`, `@type`, `builder/1,2`, `keys/0`, `enforce_keys/0`, `__information__/0`, `__fields__/0`, **`example/0`** |

Example — typo suggestion (`VerifyDeriveOps`):

```elixir
field :age, integer(), derives: "validate(intger)"   # typo
# ** (Spark.Error.DslError) unknown validate op `:intger`.
#    Did you mean `:integer`?
```

---

## 13 · Verifiers (post-compile)

> Under `lib/guarded_struct/verifiers/`.

| Verifier | What it catches |
|---|---|
| `VerifyValidatorMFA` | `validator: {Mod, :fn}` MFA actually exported |
| `VerifyAutoMFA` | `auto: {Mod, :fn}` / `auto: {Mod, :fn, :edit}` MFA exported |
| `VerifyNoStructCycles` | **NEW** A→B→A `struct:`/`structs:` cycles fail at compile time |

Example — cycle detection:

```elixir
defmodule A do
  use GuardedStruct
  guardedstruct do
    field :b, struct(), struct: B
  end
end
defmodule B do
  use GuardedStruct
  guardedstruct do
    field :a, struct(), struct: A   # cycle
  end
end
# ** (Spark.Error.DslError) struct cycle detected: A → B → A
```

---

## 14 · Mix tasks (Igniter)

> Under `lib/mix/tasks/`.

| Task | One-line description |
|---|---|
| `mix guarded_struct.install` | **NEW** Add dep, `lint` alias, seed `derive_extensions: []` |
| `mix guarded_struct.gen.struct` | **NEW** Scaffold a starter module from CLI |
| `mix guarded_struct.gen.schema` | Emit JSON Schema / TypeScript / **NEW** OpenAPI |

Install flags:

```sh
mix igniter.install guarded_struct
mix igniter.install guarded_struct --strict          # strict_derive_ops: true
mix igniter.install guarded_struct --strict-paths    # strict_core_key_paths: true
```

Scaffolder — `name!:type` marks enforce:

```sh
mix guarded_struct.gen.struct MyApp.User name!:string age:integer email:email
# => creates lib/my_app/user.ex with:
#    field :name,  String.t(), enforce: true, derives: "validate(string)"
#    field :age,   integer(),                derives: "validate(integer)"
#    field :email, String.t(),               derives: "validate(email_r)"
```

Schema emitter formats:

```sh
mix guarded_struct.gen.schema MyApp.User --format=json
mix guarded_struct.gen.schema MyApp.User --format=typescript
mix guarded_struct.gen.schema MyApp.User --format=openapi --out=priv/api.json
```

---

## 15 · Configuration (Application env)

> Read at compile-time by transformers/verifiers, runtime by `Validate`/derive runner.

| `config :guarded_struct, …` key | One-line description |
|---|---|
| `derive_extensions: [Mod, ...]` | Custom derive op modules (see §11) |
| `strict_derive_ops: true` | Unknown derive ops → `DslError` instead of runtime warning |
| `strict_core_key_paths: true` | `from:` / `on:` paths must resolve at compile time |

Example:

```elixir
# config/config.exs
config :guarded_struct,
  derive_extensions: [MyApp.Derives],
  strict_derive_ops: true,
  strict_core_key_paths: true
```

---

## 16 · Telemetry — **NEW**

> Emitted from `lib/guarded_struct/runtime.ex` (`with_telemetry/2`).
> Tests: `test/telemetry_test.exs`.

| Event | Measurements | Metadata |
|---|---|---|
| `[:guarded_struct, :builder, :start]` | `system_time` | `module` |
| `[:guarded_struct, :builder, :stop]` | `duration` | `module, result, error_count` |
| `[:guarded_struct, :builder, :exception]` | `duration` | `module, kind, reason, stacktrace` |

Only **top-level** `builder/1` emits — nested sub_field builds don't,
so you don't drown in events.

```elixir
:telemetry.attach("log-builds", [:guarded_struct, :builder, :stop],
  fn _name, %{duration: d}, %{module: m, result: r}, _ ->
    IO.puts("#{inspect(m)} #{r} in #{System.convert_time_unit(d, :native, :microsecond)}µs")
  end, nil)
```

---

## 17 · Generated functions on every `guardedstruct` module

> Emitted by `lib/guarded_struct/transformers/generate_builder.ex` and `codegen.ex`.

| Function | One-line description |
|---|---|
| `builder/1` | Build from a map: `{:ok, struct} \| {:error, errs}` |
| `builder/2` | Same with second arg `error?` flag, or input shapes `{key, attrs}` / `{key, attrs, :add\|:edit}` for path-targeted builds |
| `keys/0` | List of all field names |
| `keys/1` | List of field names matching a filter |
| `enforce_keys/0` | List of required field names |
| `enforce_keys/1` | `true`/`false` — is the named key enforced? |
| `__information__/0` | Module metadata (`keys`, `enforce_keys`, `opaque?`, `caller`, `conditional_keys`) |
| `__fields__/0` | Internal field-meta list (used by `Validate`, `Schema`, `example/0`) |
| `__guarded_validate__/1` | Apply only the validate pipeline (used by Ash extension) |
| `example/0` | **NEW** Auto-generated example struct using defaults + type fallbacks |

`__information__/0`'s `conditional_keys` is now populated with the actual
conditional-field names (was always `[]` in 0.0.x — fixed in 0.1.0).

Example — `example/0`:

```elixir
defmodule User do
  use GuardedStruct
  guardedstruct do
    field :name,  String.t(), default: "Anon"
    field :age,   integer(),  default: 0
    field :email, String.t()
    sub_field :auth, struct() do
      field :role, String.t(), default: "user"
    end
  end
end

User.example()
# => %User{name: "Anon", age: 0, email: "", auth: %User.Auth{role: "user"}}
```

Useful in iex/livebook and as a fixture in tests.

---

## 18 · `GuardedStruct.Info` — Spark info accessors

> File: `lib/guarded_struct/info.ex` — `use Spark.InfoGenerator`.

Typed accessors over compiled DSL state. Cleaner than calling
`__fields__/0` etc. directly.

| Function | One-line description |
|---|---|
| `Info.fields/1` | Spark-derived list of all field entities |
| `Info.enforce_keys/1` | Required field names for a module |
| `Info.fields_meta/1` | Same as `module.__fields__()` (alias) |
| `Info.field/2` | Look up one field's meta by name |
| `Info.field?/2` | `true`/`false` — does this field exist? |

```elixir
GuardedStruct.Info.field?(User, :email)        # => true
GuardedStruct.Info.field(User, :email).derive  # => "validate(email_r)"
```

---

## 19 · i18n / message backend — `GuardedStruct.Messages`

> File: `lib/messages.ex` (~400 LOC).

Every runtime error string goes through `translated_message/1,2`. Swap
the whole catalogue with one config key — works with Gettext, Cldr, or
any custom backend.

```elixir
defmodule MyApp.Messages do
  use GuardedStruct.Messages
  import MyAppWeb.Gettext

  def required_fields, do: gettext("Please submit required fields.")
  def email_r(field), do: gettext("Bad email on %{field}", field: field)
  # ... 60+ overridable callbacks
end

# config/config.exs
config :guarded_struct, message_backend: MyApp.Messages
```

Callback groups:

| Group | Examples |
|---|---|
| Orchestration | `required_fields/0`, `authorized_fields/0`, `builder/0`, `message_exception/0,1` |
| Cross-field | `check_dependent_keys/1`, `domain_field_status/1`, `force_domain_field_status/1` |
| List builder | `list_builder/0`, `list_builder_field_exception/0`, `list_builder_type/0` |
| Validator strings | `email_r/1`, `uuid/1`, `url/1`, `regex/1`, `not_empty/1`, `max_len_*/1`, `min_len_*/1`, ~50 more |

All 14 orchestration-layer callbacks reachable again in 0.1.0 (some were
dead in 0.0.x).

---

## 20 · `GuardedStruct.Helper.Extra` — utilities

> File: `lib/guarded_struct/helper/extra.ex`.

| Function | One-line description |
|---|---|
| `randstring/1` | Random ASCII string (non-cryptographic) |
| `validated_user?/1` | Username predicate (5-34 chars, starts with letter) |
| `validated_password?/1` | Strong password predicate (length, mixed case, digit, symbol) |
| `timestamp/0` | UTC `DateTime` truncated to microsecond |
| `get_unix_time/0` | Now as unix seconds |
| `get_unix_time_with_shift/2` | Shifted unix time |
| `app_started?/1` | Is OTP app started? |
| `erlang_guard/1`, `erlang_result/1`, `erlang_fields/4` | Match-spec helpers for `:ets` matchers |

```elixir
field :username, String.t(),
  derives: "validate(custom=GuardedStruct.Helper.Extra::validated_user?)"
```

---

## 21 · Drop-in protocol consolidation tweak

> File: `mix.exs` — `consolidate_protocols: Mix.env() != :test`.

Lets test fixtures register `Jason.Encoder` implementations after the
protocol set is normally frozen, so the `jason: true` opt actually works
in tests.

---

## 22 · Parser robustness fix

> File: `lib/guarded_struct/derive/parser.ex`.
> Caught by property tests in `test/parser_property_test.exs`.

- Switched `String.to_charlist/1` → `:binary.bin_to_list/1` so invalid
  UTF-8 doesn't crash the parser.
- Added top-level `rescue _ -> nil` to honour the lenient parser contract.
- `Code.string_to_quoted/2` now called with `emit_warnings: false` for
  fuzz-style inputs.

---

## 23 · Benchmarks

> File: `bench/builder_bench.exs`. Run with `mix run bench/builder_bench.exs`.

Three Benchee scenarios — Simple (2 fields), FieldHeavy (10 fields),
Nested (3 levels of sub_field). Baseline: ~130K builds/sec on a 2-field
struct.

---

## 24 · Tooling integration

| Tool | One-line description |
|---|---|
| `mix lint` alias | **NEW** Chains `mix spark.formatter` then `mix format` (seeded by installer) |
| `mix spark.formatter` | Works without `--extensions` flag — configured via mix alias |
| `mix spark.cheat_sheets` | Auto-generates `documentation/dsls/*.md` cheat sheets |
| `documentation/dsls/DSL-GuardedStruct.md` | Generated cheat sheet for the main DSL |
| `documentation/dsls/DSL-GuardedStruct.AshResource.md` | Generated cheat sheet for the Ash extension |
| `.formatter.exs` | `import_deps: [:spark]` so the guardedstruct block formats correctly |
| `guidance/guarded-struct.livemd` | **NEW** LiveBook tour with a "What's new in 0.1.0" section |
| ElixirSense autocomplete | Free via `Spark.ElixirSense.Plugin` (closes **#1**) |

```sh
mix lint                                   # spark.formatter + format
mix spark.cheat_sheets                     # writes documentation/dsls/*.md
```

---

## 25 · Dependencies added in 0.1.0

> File: `mix.exs`.

| Dep | Scope | Why |
|---|---|---|
| `{:spark, "~> 2.7"}` | runtime | DSL extension framework |
| `{:splode, "~> 0.3"}` | runtime | Error class hierarchy (`GuardedStruct.Errors`) |
| `{:telemetry, "~> 1.0"}` | runtime | Builder events (§16) |
| `{:igniter, "~> 0.7"}` | dev/test | Installer + scaffolder mix tasks |
| `{:sourceror, "~> 1.7"}` | dev/test | Source-mapping for installer |
| `{:stream_data, "~> 1.0"}` | test | Property-based parser tests |
| `{:benchee, "~> 1.0"}` | dev | Benchmark suite |
| `{:jason, "~> 1.0"}` | test | `jason: true` encoder tests |

Optional deps unchanged: `html_sanitize_ex`, `email_checker`, `ex_url`,
`ex_phone_number`, `sweet_xml`.

---

# Index by file

```
lib/guarded_struct.ex                         · wrapper macro, @derive_rules walker, jason: opt
lib/messages.ex                               · i18n message backend (~400 LOC, 60+ callbacks)
lib/guarded_struct/dsl.ex                     · section + all entity schemas, transformer/verifier wiring
lib/guarded_struct/dsl/field.ex               · %Field{} target (also used by dynamic_field)
lib/guarded_struct/dsl/sub_field.ex           · %SubField{} target
lib/guarded_struct/dsl/conditional_field.ex   · %ConditionalField{} target
lib/guarded_struct/dsl/virtual_field.ex       · NEW virtual_field entity
lib/guarded_struct/validate.ex                · NEW standalone Validate.run/field/partial
lib/guarded_struct/diff.ex                    · NEW diff/apply/equal? helpers
lib/guarded_struct/errors.ex                  · NEW Splode root class
lib/guarded_struct/errors/invalid.ex          · NEW :invalid error class
lib/guarded_struct/errors/validation.ex       · NEW single field-level error
lib/guarded_struct/errors/unknown.ex          · NEW uncategorised error
lib/guarded_struct/schema.ex                  · json_schema / typescript / NEW openapi
lib/guarded_struct/ash_resource.ex            · NEW Ash extension
lib/guarded_struct/ash_resource/info.ex       · NEW Ash-namespaced info accessors
lib/guarded_struct/info.ex                    · Spark.InfoGenerator wrapper
lib/guarded_struct/runtime.ex                 · build/3 + NEW telemetry wrapper
lib/guarded_struct/helper/extra.ex            · randstring, validated_user?, validated_password?, etc.
lib/guarded_struct/derive/registry.ex         · whitelist of known ops
lib/guarded_struct/derive/derive.ex           · runtime op-list runner
lib/guarded_struct/derive/op_evaluator.ex     · compile-time pre-evaluator for enum/equal operands
lib/guarded_struct/derive/extension.ex        · custom validator/sanitizer DSL
lib/guarded_struct/derive/op_param_validator.ex · NEW compile-time param shape check
lib/guarded_struct/derive/parser.ex           · UTF-8 hardened in 0.1.0
lib/guarded_struct/derive/sanitizer_derive.ex · sanitize op clauses
lib/guarded_struct/derive/validation_derive.ex · validate op clauses (incl. NEW record=Tag)
lib/guarded_struct/transformers/parse_derive.ex
lib/guarded_struct/transformers/verify_derive_ops.ex · NEW strict + typo suggestion
lib/guarded_struct/transformers/parse_core_keys.ex
lib/guarded_struct/transformers/verify_core_key_paths.ex · NEW strict path check
lib/guarded_struct/transformers/parse_domain.ex
lib/guarded_struct/transformers/generate_sub_field_modules.ex
lib/guarded_struct/transformers/generate_builder.ex
lib/guarded_struct/transformers/codegen.ex   · NEW example/0 + NEW regex-named field branch
lib/guarded_struct/transformers/generate_ash_validator.ex · NEW codegen for Ash hooks
lib/guarded_struct/verifiers/verify_validator_mfa.ex
lib/guarded_struct/verifiers/verify_auto_mfa.ex
lib/guarded_struct/verifiers/verify_no_struct_cycles.ex · NEW cycle detection
lib/mix/tasks/guarded_struct.install.ex      · NEW Igniter installer
lib/mix/tasks/guarded_struct.gen.struct.ex   · NEW scaffolder
lib/mix/tasks/guarded_struct.gen.schema.ex   · json/typescript/NEW openapi
bench/builder_bench.exs                      · NEW Benchee suite
mix.exs                                      · NEW deps + consolidate_protocols tweak + docs metadata
```

(Items marked **NEW** are net-new in 0.1.0; the rest are major rewrites
from the 0.0.x macro-based implementation.)
