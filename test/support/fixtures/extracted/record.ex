defmodule GuardedStructTest.Fixtures.Record.WithRecord do
  use GuardedStruct

  guardedstruct do
    field :any_record, :tuple, derives: "validate(record)"
    field :user_record, :tuple, derives: "validate(record=user)"
  end
end
