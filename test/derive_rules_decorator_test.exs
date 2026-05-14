defmodule GuardedStructTest.DeriveRulesDecoratorTest do
  use ExUnit.Case, async: true

  alias GuardedStructTest.Fixtures.DeriveRulesDecorator.{
    Decorated,
    Inline,
    WithAlias,
    WithBoth,
    WithSub
  }

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

  test "@derives is also accepted as an alias" do
    assert {:ok, %WithAlias{name: "ok"}} = WithAlias.builder(%{name: "ok"})

    {:error, errs} = WithAlias.builder(%{name: "this is too long"})
    assert Enum.any?(errs, &(&1[:action] == :max_len))
  end

  test "explicit derives: opt wins if both are present" do
    # Inline derives: takes precedence — long names allowed
    assert {:ok, _} = WithBoth.builder(%{name: "much longer than five chars"})
  end

  test "decorator works on sub_field too" do
    assert {:ok, _} = WithSub.builder(%{auth: %{role: "admin"}})
  end
end
