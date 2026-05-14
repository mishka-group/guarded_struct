defmodule GuardedStructTest.Fixtures.Telemetry.Sample do
  use GuardedStruct

  guardedstruct do
    field :name, String.t(), enforce: true, derives: "validate(string, max_len=80)"
    field :age, integer(), derives: "validate(integer, min_len=0)"
  end
end

defmodule GuardedStructTest.Fixtures.Telemetry.WithBoom do
  use GuardedStruct

  guardedstruct error: true do
    field :name, String.t(), enforce: true
  end
end

defmodule GuardedStructTest.Fixtures.Telemetry.WithNested do
  use GuardedStruct

  guardedstruct do
    field :name, String.t()

    sub_field :auth, struct() do
      field :role, String.t()
    end
  end
end
