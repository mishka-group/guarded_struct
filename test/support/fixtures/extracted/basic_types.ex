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
