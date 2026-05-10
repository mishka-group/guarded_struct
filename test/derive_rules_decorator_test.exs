defmodule GuardedStructTest.DeriveRulesDecoratorTest do
  use ExUnit.Case, async: true

  defmodule Decorated do
    use GuardedStruct

    guardedstruct do
      @derive_rules "validate(string, max_len=10)"
      field(:name, String.t())

      @derive_rules "validate(integer, min_len=0)"
      field(:age, integer())

      field(:plain, String.t())
    end
  end

  defmodule Inline do
    use GuardedStruct

    guardedstruct do
      field(:name, String.t(), derives: "validate(string, max_len=10)")
      field(:age, integer(), derives: "validate(integer, min_len=0)")
      field(:plain, String.t())
    end
  end

  test "decorated form parses + validates the same as inline" do
    assert {:ok, %Decorated{name: "Alice", age: 30, plain: "x"}} =
             Decorated.builder(%{name: "Alice", age: 30, plain: "x"})

    assert {:ok, %Inline{name: "Alice", age: 30, plain: "x"}} =
             Inline.builder(%{name: "Alice", age: 30, plain: "x"})
  end

  test "decorator catches the same validation errors" do
    {:error, errs} = Decorated.builder(%{name: "this name is way too long", age: -5})

    assert Enum.any?(errs, &(&1[:field] == :name and &1[:action] == :max_len))
    assert Enum.any?(errs, &(&1[:field] == :age and &1[:action] == :min_len))
  end

  test "@derive_rules is one-shot — only consumed by the very next field" do
    {:ok, %Decorated{plain: "anything works"}} =
      Decorated.builder(%{name: "ok", age: 1, plain: "anything works"})
  end

  defmodule WithAlias do
    use GuardedStruct

    guardedstruct do
      @derives "validate(string, max_len=10)"
      field(:name, String.t())
    end
  end

  test "@derives is also accepted as an alias" do
    assert {:ok, %WithAlias{name: "ok"}} = WithAlias.builder(%{name: "ok"})

    {:error, errs} = WithAlias.builder(%{name: "this is too long"})
    assert Enum.any?(errs, &(&1[:action] == :max_len))
  end

  defmodule WithBoth do
    use GuardedStruct

    guardedstruct do
      @derive_rules "validate(string, max_len=5)"
      field(:name, String.t(), derives: "validate(string, max_len=100)")
    end
  end

  test "explicit derives: opt wins if both are present" do
    # Inline derives: takes precedence — long names allowed
    assert {:ok, _} = WithBoth.builder(%{name: "much longer than five chars"})
  end

  defmodule WithSub do
    use GuardedStruct

    guardedstruct do
      @derive_rules "validate(map)"
      sub_field(:auth, struct()) do
        field(:role, String.t())
      end
    end
  end

  test "decorator works on sub_field too" do
    assert {:ok, _} = WithSub.builder(%{auth: %{role: "admin"}})
  end
end
