defmodule GuardedStructTest.NestedConditionalFieldTest do
  use ExUnit.Case, async: true

  alias GuardedStructTest.Fixtures.NestedConditionalField.{Actor, Conditional, TripleNest}

  test "compiles without raising :unsupported_conditional_field" do
    assert Code.ensure_loaded?(Conditional)
    assert function_exported?(Conditional, :builder, 1)
  end

  test "nested conditional resolves a single map → outer first child (Actor struct)" do
    {:ok, %Conditional{actor: %Actor{summary: "hello"}}} =
      Conditional.builder(%{actor: %{summary: "hello"}})
  end

  test "nested conditional resolves a string → outer last child (string url)" do
    {:ok, %Conditional{actor: "https://github.com/mishka-group"}} =
      Conditional.builder(%{actor: "https://github.com/mishka-group"})
  end

  test "nested conditional resolves a list → INNER conditional with list children" do
    {:ok, %Conditional{actor: list}} =
      Conditional.builder(%{
        actor: [
          %{summary: "Hello"},
          "https://github.com/mishka-group"
        ]
      })

    assert [%Actor{summary: "Hello"}, "https://github.com/mishka-group"] = list
  end

  test "nested conditional aggregates sibling errors when the list match fails" do
    {:error, _} = Conditional.builder(%{actor: ["bad"]})
  end

  test "nested conditional aggregates errors from the right level" do
    {:error, errors} = Conditional.builder(%{actor: 42})

    assert [
             %{
               field: :actor,
               action: :conditionals,
               errors: child_errors
             }
           ] = errors

    assert length(child_errors) >= 1
  end

  test "three-deep conditional: top-level string wins" do
    {:ok, %TripleNest{choice: "outer-match"}} = TripleNest.builder(%{choice: "outer-match"})
  end

  test "three-deep conditional: unmatched value returns a 3-level aggregated error" do
    assert {:error, [%{field: :choice, action: :conditionals, errors: level1_errs}]} =
             TripleNest.builder(%{choice: %{}})

    assert Enum.any?(level1_errs, &match?(%{__hint__: "level1_string"}, &1))

    assert %{action: :conditionals, errors: level2_errs} =
             Enum.find(level1_errs, &match?(%{action: :conditionals}, &1))

    assert Enum.any?(level2_errs, &match?(%{__hint__: "level2_string"}, &1))

    assert %{action: :conditionals, errors: level3_errs} =
             Enum.find(level2_errs, &match?(%{action: :conditionals}, &1))

    assert Enum.any?(level3_errs, &match?(%{__hint__: "level3_string"}, &1))
    assert Enum.any?(level3_errs, &match?(%{__hint__: "level3_int"}, &1))
  end
end
