defmodule GuardedStructTest.NestedSubFieldTest do
  use ExUnit.Case, async: true

  alias GuardedStructTest.Fixtures.NestedSubField.NestedSubFieldListStructs

  test "nested sub field list structs" do
    assert {:ok, _struct} =
             NestedSubFieldListStructs.builder(%{
               list: [%{id: "1", sublist: [%{id: "1"}]}]
             })
  end
end
