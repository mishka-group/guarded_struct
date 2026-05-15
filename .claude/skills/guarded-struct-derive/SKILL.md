---
name: guarded-struct-derive
description: Use when writing or modifying `derives:` strings on guarded fields, when invoking `GuardedStruct.Derive.SanitizerDerive.sanitize/2` or `ValidationDerive.call/3` directly, or when debugging `:sanitize` / `:validate` op errors. Covers the full grammar of `sanitize(...) validate(...)`, every built-in op atom, the pipe-friendly `(value, op)` arg order, and the five accepted derive syntaxes.
---

# Derive ops

Reference: `usage-rules/derive.md`.

## Grammar

```
"sanitize(<op>, <op>, ...) validate(<op>, <op>, ...)"
```

Each op is an atom or `atom=operand`. The string is parsed at compile time into
`__derive_ops__: %{sanitize: [op, ...], validate: [op, ...]}`. Operands like
`enum=String[a::b::c]` are pre-evaluated at compile time into structured tuples
(`{:enum, ["a", "b", "c"]}`).

## Built-in op atoms

Live source of truth: `lib/guarded_struct/derive/registry.ex`. Current set:

**Sanitize:** `:trim`, `:upcase`, `:downcase`, `:capitalize`, `:basic_html`,
`:html5`, `:markdown_html`, `:strip_tags`, `:tag`, `:string_float`,
`:string_integer`.

**Validate (types):** `:string`, `:integer`, `:float`, `:number`, `:list`,
`:map`, `:tuple`, `:atom`, `:boolean`, `:bitstring`, `:struct`, `:exception`,
`:function`, `:pid`, `:port`, `:reference`, `:nil_value`, `:not_nil_value`.

**Validate (content/format):** `:not_empty`, `:not_empty_string`,
`:not_flatten_empty`, `:not_flatten_empty_item`, `:queue`, `:max_len`,
`:min_len`, `:url`, `:tell`, `:geo_url`, `:email`, `:email_r`, `:location`,
`:string_boolean`, `:datetime`, `:range`, `:date`, `:regex`, `:ipv4`, `:uuid`,
`:username`, `:full_name`, `:enum`, `:equal`, `:custom`, `:either`, `:record`,
`:string_float`, `:string_integer`, `:some_string_float`, `:some_string_integer`.

## Pipe-friendly direct API

```elixir
alias GuardedStruct.Derive.SanitizerDerive
"  Alice@X.IO  " |> SanitizerDerive.sanitize(:trim) |> SanitizerDerive.sanitize(:downcase)
# => "alice@x.io"
```

The arg order is `(value, op)`. The same convention extends to
`Extension.dispatch_sanitize(input, op)` and to user-defined extension
sanitizer callbacks (`__sanitize__(input, op)`).

## Five accepted input syntaxes

All normalize to the same internal op map:

```elixir
# 1. String (canonical)
field :x, :string, derives: "sanitize(trim) validate(string)"

# 2. @derives decorator
@derives "sanitize(trim) validate(string)"
field :x, :string

# 3. Keyword form
field :x, :string, derive: [sanitize: [:trim], validate: [:string]]

# 4. Block form
field :x, :string do
  sanitize :trim
  validate :string
end

# 5. Pipe form
field :x, :string,
  derive: GuardedStruct.Sanitize.trim() |> GuardedStruct.Validate.string()
```

## Validate boundary semantics

`{:min_len, n}` and `{:max_len, n}` use `String.length/1` on binaries, value
comparison on integers/floats, range size on Ranges, and `length/1` on lists.
The classifier is **inclusive** on both bounds (`<=` / `>=`).

## Standalone API

```elixir
GuardedStruct.Validate.run("validate(email_r)", "alice@x.io")
# => {:ok, "alice@x.io"}

GuardedStruct.Validate.field(MyApp.User, :email, "bad")
# => {:error, [%{field: :email, action: :email_r, message: ...}]}
```
