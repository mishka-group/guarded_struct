defmodule GuardedStructTest.ExampleHelperTest do
  use ExUnit.Case, async: true

  alias GuardedStructTest.Fixtures.ExampleHelper.{WithDefaults, TypeFallbacks, Nested}

  test "example/0 uses declared defaults" do
    sample = WithDefaults.example()
    assert sample.name == "default name"
    assert sample.age == 42
    assert sample.active == true
  end

  test "example/0 falls back to type-based placeholders" do
    sample = TypeFallbacks.example()
    assert sample.name == ""
    assert sample.count == 0
    assert sample.rate == 0.0
    assert sample.active == false
    assert sample.tags == []
    assert sample.metadata == %{}
  end

  test "nested sub_field example/0 recurses" do
    sample = Nested.example()
    assert sample.title == "the title"
    assert is_struct(sample.meta)
    assert sample.meta.author == "anon"
    assert sample.meta.year == 2026
  end

  test "example/0 returns a struct of the declaring module" do
    assert %WithDefaults{} = WithDefaults.example()
    assert %Nested{} = Nested.example()
    assert %Nested.Meta{} = Nested.example().meta
  end
end
