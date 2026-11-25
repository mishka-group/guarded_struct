defmodule GuardedStruct.EqualDeriveTest do
  # `validate(equal=Type::value)` in a field's `derives:` string compiles, but the built struct
  # comes back with the field set to nil and nothing is checked. `ValidationDerive.validate/3`
  # called directly with `{:equal, "String::name"}` works (see derive_test.exs), so the problem is
  # between the derive string and the op the builder runs.
  use ExUnit.Case, async: true

  defmodule Plain do
    use GuardedStruct

    guardedstruct do
      field(:role, String.t(), derives: "validate(string)")
    end
  end

  defmodule StringEqual do
    use GuardedStruct

    guardedstruct do
      field(:role, String.t(), derives: "validate(equal=String::admin)")
    end
  end

  defmodule IntegerEqual do
    use GuardedStruct

    guardedstruct do
      field(:count, integer(), derives: "validate(equal=Integer::3)")
    end
  end

  test "a field with another derive keeps its value" do
    assert {:ok, %Plain{role: "admin"}} = Plain.builder(%{role: "admin"})
  end

  test "equal=String:: keeps a value that matches" do
    assert {:ok, %StringEqual{role: "admin"}} = StringEqual.builder(%{role: "admin"})
  end

  test "equal=String:: refuses a value that does not match" do
    assert {:error, errors} = StringEqual.builder(%{role: "editor"})
    assert Enum.any?(errors, &(&1.field == :role and &1.action == :equal))
  end

  test "equal=Integer:: keeps a value that matches" do
    assert {:ok, %IntegerEqual{count: 3}} = IntegerEqual.builder(%{count: 3})
  end

  test "equal=Integer:: refuses a value that does not match" do
    assert {:error, errors} = IntegerEqual.builder(%{count: 4})
    assert Enum.any?(errors, &(&1.field == :count and &1.action == :equal))
  end
end
