defmodule GuardedStructTest.Fixtures.NestedSubField.NestedSubFieldListStructs do
  use GuardedStruct

  guardedstruct do
    sub_field :list,
              list(struct()),
              structs: true,
              derives: "validate(list, not_empty)",
              enforce: true do
      field :id, String.t(), enforce: true

      sub_field :sublist,
                list(struct()),
                structs: true,
                derives: "validate(list, not_empty)",
                enforce: true do
        field :id, String.t()
      end
    end
  end
end
