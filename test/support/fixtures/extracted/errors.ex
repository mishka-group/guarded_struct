# Fixtures for `test/errors_test.exs`. Top-level so `Spark.Formatter`
# can strip parens (it skips nested defmodules — see commit history).

defmodule GuardedStructTest.Fixtures.Errors.SampleStruct do
  use GuardedStruct

  guardedstruct do
    field :email, String.t(), enforce: true, derives: "validate(string, email_r)"
    field :age, integer(), derives: "validate(integer, max_len=120, min_len=0)"
  end
end
