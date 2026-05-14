defmodule GuardedStructTest.Fixtures.ExampleHelper.WithDefaults do
  use GuardedStruct

  guardedstruct do
    field :name, String.t(), default: "default name"
    field :age, integer(), default: 42
    field :active, boolean(), default: true
  end
end

defmodule GuardedStructTest.Fixtures.ExampleHelper.TypeFallbacks do
  use GuardedStruct

  guardedstruct do
    field :name, String.t()
    field :count, integer()
    field :rate, float()
    field :active, boolean()
    field :tags, list()
    field :metadata, map()
  end
end

defmodule GuardedStructTest.Fixtures.ExampleHelper.Nested do
  use GuardedStruct

  guardedstruct do
    field :title, String.t(), default: "the title"

    sub_field :meta, struct() do
      field :author, String.t(), default: "anon"
      field :year, integer(), default: 2026
    end
  end
end
