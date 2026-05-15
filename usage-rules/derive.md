# Derive ops — `sanitize(...)` and `validate(...)` mini-language

`derives:` accepts a string parsed at **compile time** into a normalized op map.
Typos surface as `Spark.Error.DslError`. The runtime never re-parses.

```elixir
field :email, :string,
  derives: "sanitize(trim, downcase) validate(string, not_empty, email_r, max_len=320)"
```

## Grammar

```
<derive>   ::= <group>+
<group>    ::= "sanitize(" <ops> ")"  |  "validate(" <ops> ")"
<ops>      ::= <op> ("," <op>)*
<op>       ::= <atom> | <atom> "=" <operand>
<operand>  ::= literal | "Type[...]" | "Map::..."
```

The same logical rules also support a keyword/block/pipe form (see source-level
docs), but the string form above is the canonical input.

## Built-in sanitize ops (`GuardedStruct.Derive.Registry.@sanitize_ops`)

| Op | Effect |
|---|---|
| `:trim` | `String.trim/1` if binary; passthrough otherwise. |
| `:upcase` / `:downcase` / `:capitalize` | Corresponding `String.*` calls. |
| `:strip_tags` | `HtmlSanitizeEx.strip_tags/1` (optional dep). |
| `:basic_html` / `:html5` / `:markdown_html` | Whitelisted HTML cleanup (optional dep). |
| `{:tag, op_atom}` | `trim → op → trim`. |
| `:string_float` / `:string_integer` | Parse numeric out of a string; returns `0`/`0.0` on failure. |

Arg order is **pipe-friendly**: `SanitizerDerive.sanitize(value, :op)`.

## Built-in validate ops (`GuardedStruct.Derive.Registry.@validate_ops`)

Type guards: `:string`, `:integer`, `:float`, `:number`, `:list`, `:map`,
`:tuple`, `:atom`, `:boolean`, `:bitstring`, `:struct`, `:exception`,
`:function`, `:pid`, `:port`, `:reference`, `:nil_value`, `:not_nil_value`.

Content / format:

| Op | Constraint |
|---|---|
| `:not_empty`, `:not_empty_string` | Non-zero length. |
| `:not_flatten_empty`, `:not_flatten_empty_item` | List-shape contracts. |
| `{:min_len, n}` / `{:max_len, n}` | Bounds. Apply to strings, integers, floats, ranges, lists. |
| `:email`, `:email_r` | DNS-checked vs regex-only. `email_r` is data-layer safe. |
| `:url`, `:tell`, `:geo_url` | URL/phone/geo via `URL`/`ExPhoneNumber` (optional). |
| `:uuid`, `:ipv4`, `:datetime`, `:date`, `:range`, `:regex` | Format checks. |
| `:username`, `:full_name`, `:location`, `:queue`, `:string_boolean` | Domain checks (see `lib/guarded_struct/helper/extra.ex`). |
| `{:enum, "String[a::b::c]"}` etc. | Membership against compile-evaluated list. |
| `{:equal, _}` | Equality. |
| `{:either, _}`, `{:custom, _}` | Composition / user-supplied predicate. |
| `:record` | Erlang record shape. |

## Op flow

1. Parse `derives:` string at compile time → `__derive_ops__: %{sanitize: [...], validate: [...]}`.
2. Pre-evaluate operands like `enum=String[a::b::c]` → `{:enum, ["a", "b", "c"]}` at compile time.
3. Runtime applies ops in declared order: sanitize first, then validate.
4. Errors emerge as a flat list of `%{field, action, message}` maps.

## Five accepted derive syntaxes

* String form (canonical, above).
* `@derives` decorator (set on the next entity).
* Keyword form: `derive: [sanitize: [:trim], validate: [:string]]`.
* Block form inside the entity.
* Pipe form via `GuardedStruct.Sanitize` / `GuardedStruct.Validate` helpers.

All five normalize to the same internal op map.

## Direct API

```elixir
GuardedStruct.Derive.SanitizerDerive.sanitize("  Hello  ", :trim)        # => "Hello"
"  Hello  " |> SanitizerDerive.sanitize(:trim) |> SanitizerDerive.sanitize(:downcase)
GuardedStruct.Derive.ValidationDerive.call({:email, "a@b"}, [:email_r], [])  # {processed, errors}
GuardedStruct.Validate.run("validate(uuid)", "11111111-2222-3333-4444-555555555555")
```
