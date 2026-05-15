# Custom validators — `validator:` and `main_validator:`

Two hook points complement the declarative `derives:` pipeline:

* **`validator: {Mod, :fn}`** on a field — runs per-value, before derives.
* **`main_validator: {Mod, :fn}`** in the section — runs once after every field
  validates, gets the full attribute map.

## Per-field validator

```elixir
field :age, :integer, validator: {MyApp.Checks, :positive_only}

defmodule MyApp.Checks do
  def positive_only(:age, v) when is_integer(v) and v > 0, do: {:ok, :age, v}
  def positive_only(:age, _), do: {:error, :age, "must be positive"}
end
```

Return shape:

| Return | Effect |
|---|---|
| `{:ok, name, new_value}` | Replace value with `new_value`, continue. |
| `{:error, name, message}` | Emit `%{field: name, action: :validator, message: message}`. |
| anything else | Treated as `{:ok, value}` (no change). |

Compile-time verifier `VerifyValidatorMFA` rejects the module if the MFA
doesn't exist.

## Section-level `main_validator`

```elixir
guardedstruct main_validator: {MyApp.Checks, :ensure_consistent} do
  field :a, :string
  field :b, :string
end

def ensure_consistent(%{a: a, b: b} = attrs) do
  if a == b, do: {:ok, attrs}, else: {:error, %{field: :__root__, action: :main_validator, message: "a must equal b"}}
end
```

Return shape:

| Return | Effect |
|---|---|
| `{:ok, attrs}` | Use the (possibly transformed) map for the rest of the pipeline. |
| `{:error, errs}` (list or single map) | Emit error(s). Single maps are wrapped in a list. |
| anything else | Treated as `{:ok, attrs}`. |

## Caller-module fallback (no opts needed)

If you don't pass `validator:` / `main_validator:` but the module itself
defines `def validator(field, value)` or `def main_validator(attrs)`, the
runtime uses those automatically (legacy 0.0.x compat).

Compile-time-baked flags (`__guarded_has_validator__/0`,
`__guarded_has_main_validator__/0`) make this a zero-cost check — no
`function_exported?` at runtime.

## Notes

* Use `validator:` for shape / business rules that can't be expressed as a
  built-in `validate(_)` op. For composable type/length/format work, prefer
  declarative derives — they survive Ash atomic mode and the standalone
  `Validate.run/2` API.
* `main_validator` runs in **non-atomic** Ash paths only when no other field
  triggers `{:not_atomic, _}`. In pure standalone mode it always runs.
