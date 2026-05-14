defmodule GuardedStructTest.Fixtures.Diff.User do
  use GuardedStruct

  guardedstruct do
    field :name, String.t(), enforce: true
    field :age, integer()
    field :role, String.t()

    sub_field :address, struct() do
      field :city, String.t()
      field :zip, String.t()
    end
  end
end

defmodule GuardedStructTest.Fixtures.Diff.Other do
  defstruct [:x]
end

defmodule GuardedStructTest.Fixtures.Diff.Other2 do
  defstruct [:x]
end
