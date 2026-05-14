defmodule GuardedStructTest.Fixtures.DeriveRulesDecorator.Decorated do
  use GuardedStruct

  guardedstruct do
    @derive_rules "validate(string, max_len=10)"
    field :name, String.t()

    @derive_rules "validate(integer, min_len=0)"
    field :age, integer()

    field :plain, String.t()
  end
end

defmodule GuardedStructTest.Fixtures.DeriveRulesDecorator.Inline do
  use GuardedStruct

  guardedstruct do
    field :name, String.t(), derives: "validate(string, max_len=10)"
    field :age, integer(), derives: "validate(integer, min_len=0)"
    field :plain, String.t()
  end
end

defmodule GuardedStructTest.Fixtures.DeriveRulesDecorator.WithAlias do
  use GuardedStruct

  guardedstruct do
    @derives "validate(string, max_len=10)"
    field :name, String.t()
  end
end

defmodule GuardedStructTest.Fixtures.DeriveRulesDecorator.WithBoth do
  use GuardedStruct

  guardedstruct do
    @derive_rules "validate(string, max_len=5)"
    field :name, String.t(), derives: "validate(string, max_len=100)"
  end
end

defmodule GuardedStructTest.Fixtures.DeriveRulesDecorator.WithSub do
  use GuardedStruct

  guardedstruct do
    @derive_rules "validate(map)"
    sub_field :auth, struct() do
      field :role, String.t()
    end
  end
end
