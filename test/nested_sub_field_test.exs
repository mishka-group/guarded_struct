# TODO:
# It is based on these issues and we need to fix 12 if we want to support nested list sub fields:
# 1. https://github.com/mishka-group/guarded_struct/issues/12
# 2. https://github.com/mishka-group/guarded_struct/issues/7

defmodule GuardedStructTest.NestedSubFieldTest do
  use ExUnit.Case, async: true

  defmodule NestedSubFieldListStructs do
    use GuardedStruct

    guardedstruct do
      sub_field(:list, list(struct()),
        structs: true,
        derive: "validate(list, not_empty)",
        enforce: true
      ) do
        field(:id, String.t(), enforce: true)

        sub_field(:sublist, list(struct()),
          structs: true,
          derive: "validate(list, not_empty)",
          enforce: true
        ) do
          field(:id, String.t())
        end
      end
    end
  end

  test "nested sub field list structs" do
    true
    # assert {:ok, _struct} =
    #          NestedSubFieldListStructs.builder(%{
    #            list: [%{id: "1", sublist: [%{id: "1"}]}]
    #          })

    # assert {:ok, struct} =
    #          NestedSubFieldListStructs.builder(
    #            list: [
    #              %{id: "1", sublist: [%{id: "1"}]},
    #              %{id: "2", sublist: [%{id: "2"}]}
    #            ]
    #          )

    # assert {:error, _error} =
    #          NestedSubFieldListStructs.builder(
    #            list: [
    #              %{id: "1", sublist: [%{id: "1"}]},
    #              %{id: "2", sublist: [%{id: "2"}]}
    #            ]
    #          )

    # assert {:error, _error} =
    #          NestedSubFieldListStructs.builder(
    #            list: [
    #              %{id: "1", sublist: [%{id: "1"}]},
    #              %{id: "2", sublist: [%{id: "2"}]}
    #            ]
    #          )
  end
end
