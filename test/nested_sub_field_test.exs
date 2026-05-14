# TODO:
# It is based on these issues and we need to fix 12 if we want to support nested list sub fields:
# 1. https://github.com/mishka-group/guarded_struct/issues/12
# 2. https://github.com/mishka-group/guarded_struct/issues/7

defmodule GuardedStructTest.NestedSubFieldTest do
  use ExUnit.Case, async: true

  alias GuardedStructTest.Fixtures.NestedSubField.NestedSubFieldListStructs
  _ = NestedSubFieldListStructs

  test "nested sub field list structs" do
    true
    # assert {:ok, _struct} =
    #          NestedSubFieldListStructs.builder(%{
    #            list: [%{id: "1", sublist: [%{id: "1"}]}]
    #          })
  end
end
