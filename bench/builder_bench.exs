# Benchmarks for `MyStruct.builder/1` — verifies the compile-time-parsing
# claim and provides a baseline for regressions.
#
# Run with:  mix run bench/builder_bench.exs

defmodule Bench.SimpleStruct do
  use GuardedStruct

  guardedstruct do
    field(:name, String.t(), enforce: true, derive: "validate(string, max_len=80)")
    field(:age, integer(), derive: "validate(integer, min_len=0, max_len=120)")
  end
end

defmodule Bench.FieldHeavy do
  use GuardedStruct

  guardedstruct do
    field(:f1, String.t(), derive: "sanitize(trim) validate(string, max_len=20)")
    field(:f2, String.t(), derive: "sanitize(trim, downcase) validate(email_r)")
    field(:f3, integer(), derive: "validate(integer, min_len=0, max_len=120)")
    field(:f4, String.t(), derive: "validate(uuid)")
    field(:f5, String.t(), derive: "validate(url)")
    field(:f6, String.t(), derive: "validate(enum=String[a::b::c::d::e])")
    field(:f7, String.t(), derive: "validate(string, not_empty)")
    field(:f8, integer(), derive: "validate(integer)")
    field(:f9, boolean(), derive: "validate(boolean)")
    field(:f10, String.t(), derive: "sanitize(trim) validate(string, max_len=200)")
  end
end

defmodule Bench.Nested do
  use GuardedStruct

  guardedstruct do
    field(:name, String.t(), derive: "validate(string)")

    sub_field(:auth, struct()) do
      field(:email, String.t(), derive: "validate(email_r)")
      field(:role, String.t(), derive: "validate(enum=String[admin::user::guest])")

      sub_field(:profile, struct()) do
        field(:bio, String.t(), derive: "validate(string, max_len=500)")
      end
    end
  end
end

simple_input = %{name: "Alice", age: 30}

field_heavy_input = %{
  f1: "  hi  ",
  f2: "Alice@Example.COM",
  f3: 42,
  f4: "11111111-2222-3333-4444-555555555555",
  f5: "https://example.com",
  f6: "a",
  f7: "value",
  f8: 100,
  f9: true,
  f10: "long text"
}

nested_input = %{
  name: "Alice",
  auth: %{
    email: "alice@example.com",
    role: "admin",
    profile: %{bio: "hello world"}
  }
}

Benchee.run(
  %{
    "Simple — 2 fields, 1 derive each" => fn -> Bench.SimpleStruct.builder(simple_input) end,
    "FieldHeavy — 10 fields, mixed derives" => fn ->
      Bench.FieldHeavy.builder(field_heavy_input)
    end,
    "Nested — 3 levels deep" => fn -> Bench.Nested.builder(nested_input) end
  },
  time: 3,
  memory_time: 1,
  warmup: 1,
  print: [fast_warning: false]
)
