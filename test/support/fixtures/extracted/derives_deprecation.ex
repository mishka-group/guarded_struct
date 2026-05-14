defmodule GuardedStructTest.Fixtures.DerivesDeprecation.CanonicalName do
  use GuardedStruct

  guardedstruct do
    field :name, String.t(), derives: "validate(string, max_len=10)"
  end
end
