defmodule GuardedStructTest.Fixtures.BasicTypes.EnforcedGuardedStruct do
  use GuardedStruct

  guardedstruct enforce: true do
    field :enforced_by_default, term()
    field :not_enforced, term(), enforce: false
    field :with_default, integer(), default: 1
    field :with_false_default, boolean(), default: false
    field :with_nil_default, term(), default: nil
  end

  def enforce_keys, do: @enforce_keys
end

defmodule GuardedStructTest.Fixtures.BasicTypes.NonAstDefaults do
  # Defaults that are NOT valid AST literals (maps, 3+-tuples) must still
  # survive the `defstruct unquote(...)` codegen path — both at the top
  # level and inside a sub_field submodule.
  use GuardedStruct

  guardedstruct do
    field :helpers, map(), default: %{}
    field :coords, tuple(), default: {:x, :y, :z}

    sub_field :inner, map(), default: %{} do
      field :tags, list(), default: []
      field :meta, map(), default: %{}
      field :triple, tuple(), default: {1, 2, 3}
    end
  end
end
