# Changelog for GuardedStruct 0.1.0

Major release. The macro core has been rewritten on top of [Spark](https://hex.pm/packages/spark). Public API is fully backward-compatible — every existing call (`use GuardedStruct`, `guardedstruct opts do … end`, `field`, `sub_field`, `conditional_field`, `MyStruct.builder/1,2`, `MyStruct.keys/0,1`, `MyStruct.enforce_keys/0,1`, `MyStruct.__information__/0`) works unchanged.

See [`MIGRATION.md`](./MIGRATION.md) for the upgrade story.

## Architecture

- Rewrote the 2,910-LOC macro core on `Spark.Dsl.Extension`. The new core is one `:guardedstruct` section, four entities (`field`, `sub_field`, `conditional_field`, `virtual_field`, plus a `dynamic_field` shorthand), six transformers, and two verifiers.
- Moved every static-string parse to compile time. Derive op-strings, `from:`/`on:` paths, and `domain:` patterns are now parsed once during compilation; the runtime reads pre-built op-maps from `__fields__/0` and never re-parses on each `builder/1` call.
- Pre-evaluated `enum=Map[…]` / `enum=Tuple[…]` / `equal=Map::…` operands at compile time. Zero `Code.eval_string` calls on the runtime hot path.
- Editor autocomplete inside `guardedstruct do … end` blocks via Spark's ElixirSense plugin (closes #1).

## New features

### Pattern-keyed maps (closes #11)

A `field` whose name is a regex declares a pattern-keyed map. The struct's `builder/1` returns a plain validated map (no struct generated, since Elixir struct keys are fixed):

```elixir
defmodule ShardsMap do
  use GuardedStruct
  guardedstruct do
    field ~r/^shard_\d+$/, struct(), struct: Shard, derive: "validate(map, not_empty)"
  end
end

ShardsMap.builder(%{"shard_1" => %{node: "10.0.0.1"}, "shard_2" => %{node: "10.0.0.2"}})
# {:ok, %{"shard_1" => %Shard{...}, "shard_2" => %Shard{...}}}
```

Mixing atom-keyed and regex-keyed `field`s in the same `guardedstruct` raises `Spark.Error.DslError` at compile time. Keys stay as strings (atom-table-exhaustion safe by default).

### Erlang Record support (closes #6)

Two new validate ops:

```elixir
field :user_record, :tuple, derive: "validate(record=user)"
# accepts {:user, "Alice", 30}; rejects other tags
```

### `virtual_field` (closes #5)

Validated through the full pipeline but excluded from `defstruct`. Useful for `password_confirm`-style fields needed only by `main_validator/1`.

### `dynamic_field`

Shorthand for a `field` whose value is a free-form map (default `%{}`, type `map()`, derive `validate(map)`).

`dynamic_field` values are **identity-preserved** — whatever you submit (string keys, atom keys, mixed, nested) round-trips byte-identical to `builder/1`'s output. No string-to-atom conversion of inner keys at any depth, to prevent atom-table-exhaustion DoS. See the "Atom-attack safety" section of the `GuardedStruct` module @moduledoc for details.

### `GuardedStruct.Validate` (closes #2)

Three-tier API for using a schema without going through `builder/1`:

```elixir
Validate.run("validate(string, max_len=80, email_r)", "alice@example.com")
# {:ok, "alice@example.com"}

Validate.field(User, :email, "alice@x.com")
# {:ok, "alice@x.com"}

Validate.field(User, :parent_email, "p@x.com", context: %{account_type: "personal"})
# resolves cross-field on:/domain: deps from context

Validate.field(User, :parent_email, "p@x.com", mode: :isolated)
# skips cross-field deps entirely

Validate.partial(User, %{name: "", email: "alice@x.com"})
# subset validation; missing fields skipped (no enforce_keys check)
```

### Custom validators / sanitizers via Spark-native DSL

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

Coexists with the legacy `Application.put_env(:guarded_struct, :validate_derive, …)` plug-in mechanism.

### Splode error class

Opt-in wrapper for runtime errors:

```elixir
{:error, errs} = MyStruct.builder(input)
class = GuardedStruct.Errors.from_tuple(errs)
GuardedStruct.Errors.traverse_errors(class, &Exception.message/1)
```

### Ash extension

```elixir
defmodule MyApp.Resource do
  use Ash.Resource, extensions: [GuardedStruct.AshResource]

  guardedstruct do
    field :name, :string, enforce: true, derives: "validate(string)"
  end

  changes do
    change GuardedStruct.AshResource.Change
  end
end
```

The extension generates **prefixed** functions to avoid clashing with Ash's own callbacks:

* `__guarded_change__/1` — runs the full GuardedStruct pipeline (sanitize → validate → derive → main_validator) and returns `{:ok, transformed_attrs} | {:error, errors}`. Named `change` (not `validate`) because the pipeline can transform values, not just inspect them.
* `__guarded_information__/0` and `__guarded_fields__/0` — introspection, mirroring the standalone API.

The companion `GuardedStruct.AshResource.Change` module is a ready-made `Ash.Resource.Change` that bridges `__guarded_change__/1` into the changeset pipeline. Two wiring modes:

* **Manual (default)** — write `changes do change GuardedStruct.AshResource.Change end` once. Explicit, inspectable via `Ash.Resource.Info.changes/1`.
* **Auto-wire** — set `auto_wire true` at the top of `guardedstruct`. A Spark transformer injects the change for you via `Ash.Resource.Builder.add_change/3`. No `changes do ... end` block needed. Default is `false`.

## Soft deprecations

- **`derive:` option renamed to `derives:`**. Both work in `0.1.0`; the legacy `derive:` emits a compile-time deprecation warning via `Spark.Warning.warn_deprecated/4` and will be removed in a future release. The plural form aligns with the `@derives` decorator. When both are present on the same field, `derives:` wins silently.

  ```elixir
  # new canonical form
  field :email, String.t(), derives: "sanitize(trim) validate(email_r)"

  # legacy form, still works but warns
  field :email, String.t(), derive: "sanitize(trim) validate(email_r)"
  ```

## Bug fixes

- **Closes #7, #8, #25**: nested `conditional_field` works to arbitrary depth via `recursive_as: :conditional_fields`. Three-level deep tested in `test/nested_conditional_field_test.exs`.
- Restored i18n via `GuardedStruct.Messages.translated_message/1,2` for orchestration-layer errors (`authorized_fields`, `required_fields`, `:on` / `:domain` core keys, list-builder errors). All 14 message callbacks reachable again.
- `__information__/0` now populates `conditional_keys` with the actual conditional-field names (was always `[]`).
- `MyStruct.Error.message/1` matches master's format and uses `translated_message(:message_exception)` for i18n.
- Unblocked the legacy `Parser` raise sites that prevented nested conditional_field from compiling.

## Other improvements

- Strict compile-time errors for malformed `derive:` strings via `Spark.Error.DslError` with file:line.
- Op-name registry — single source of truth for built-in ops, lives at `lib/guarded_struct/derive/registry.ex`.
- `mix lint` alias chains `mix spark.formatter` then `mix format`.
- `mix spark.formatter` and `mix spark.cheat_sheets` work without the `--extensions` flag (configured via mix alias).

## Internals dropped

These were `@doc false` internal API in `0.0.x`; if any user code reached for them, it was unsupported. They're gone:

- The `builder/4` form on `GuardedStruct` (with `(actions, key, type, error)` arity) — replaced by an internal runtime helper
- `register_struct/4`, `__field__/6`, `__type__/2`, `delete_temporary_revaluation/1`, `create_builder/1`, `create_error_module/0`
- The 12 `gs_*` accumulator module attributes (`gs_fields`, `gs_types`, `gs_enforce_keys`, etc.) — replaced by Spark DSL state
- `parser/3` (the conditional variant of `Parser.parser`), `elements_unification/2`, `find_node_tags/1`, `add_parent_tags/3`, `conds_list/2`, `find_conds_children_recursive/2`
- `Derive.pre_derives_check/3`, `get_derives_from_success_conditional_data/1`, `error_handler/2`, `halt_errors/1`, the alternate-shape `derive/1` clauses
- `Messages.unsupported_conditional_field/0` and `Messages.parser_field_value/0` callbacks (dead code after the nested-conditional fix)

## Dependencies

- Added: `{:spark, "~> 2.7"}`, `{:splode, "~> 0.3"}`
- Added (`:dev, :test` only): `{:sourceror, "~> 1.7"}`, `{:igniter, "~> 0.7"}`
- All optional deps unchanged (`html_sanitize_ex`, `email_checker`, `ex_url`, `ex_phone_number`, `sweet_xml`)

## Test counts

- `0.0.4`: 146 tests
- `0.1.0`: 280 tests, all passing

---

# Changelog for GuardedStruct 0.0.4

- Fix deprecated code from Elixir 1.18
- Support overridable messages for the `GuardedStruct` module with support for multiple languages

# Changelog for GuardedStruct 0.0.3

- Fix deprecated code from Elixir 1.18.0-rc.0

# Changelog for GuardedStruct 0.0.2

- Fix: Support charlists sigil warning and keep backward compatibility for charlist regex

# Changelog for GuardedStruct 0.0.1

- Detach from the Mishka developer tools library
- Remove optional libraries (must be enabled by the user)
- Improvements in some tests
