defmodule GuardedStructTest.Fixtures.JsonEncoder.Plain do
  use GuardedStruct

  guardedstruct do
    field :name, String.t(), enforce: true
    field :age, integer()
  end
end

defmodule GuardedStructTest.Fixtures.JsonEncoder.WithJason do
  use GuardedStruct

  guardedstruct json: true do
    field :name, String.t(), enforce: true
    field :age, integer()
  end
end

defmodule GuardedStructTest.Fixtures.JsonEncoder.Nested do
  use GuardedStruct

  guardedstruct json: true do
    field :name, String.t(), enforce: true

    sub_field :address, struct() do
      field :city, String.t(), enforce: true
      field :zip, String.t()
    end
  end
end
