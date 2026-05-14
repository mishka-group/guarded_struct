defmodule GuardedStructTest.DiffTest do
  use ExUnit.Case, async: true

  alias GuardedStruct.Diff
  alias GuardedStructTest.Fixtures.Diff.{User, Other, Other2}

  describe "diff/2" do
    test "two equal structs return %{}" do
      {:ok, a} = User.builder(%{name: "Alice", age: 30, role: "admin"})
      {:ok, b} = User.builder(%{name: "Alice", age: 30, role: "admin"})

      assert Diff.diff(a, b) == %{}
    end

    test "primitive field change returns :changed tuple" do
      {:ok, a} = User.builder(%{name: "Alice", age: 30})
      {:ok, b} = User.builder(%{name: "Alice", age: 31})

      assert Diff.diff(a, b) == %{age: {:changed, 30, 31}}
    end

    test "multiple field changes are aggregated" do
      {:ok, a} = User.builder(%{name: "Alice", age: 30, role: "admin"})
      {:ok, b} = User.builder(%{name: "Bob", age: 31, role: "admin"})

      assert %{name: {:changed, "Alice", "Bob"}, age: {:changed, 30, 31}} = Diff.diff(a, b)
    end

    test "nested struct change recurses" do
      {:ok, a} = User.builder(%{name: "Alice", address: %{city: "NYC", zip: "10001"}})
      {:ok, b} = User.builder(%{name: "Alice", address: %{city: "Chicago", zip: "10001"}})

      assert %{address: %{city: {:changed, "NYC", "Chicago"}}} = Diff.diff(a, b)
    end

    test "nested struct unchanged → not in diff" do
      {:ok, a} = User.builder(%{name: "Alice", address: %{city: "NYC", zip: "10001"}})
      {:ok, b} = User.builder(%{name: "Bob", address: %{city: "NYC", zip: "10001"}})

      result = Diff.diff(a, b)
      refute Map.has_key?(result, :address)
      assert Map.has_key?(result, :name)
    end

    test "two structs of different types return :not_comparable" do
      {:ok, a} = User.builder(%{name: "Alice"})

      assert Diff.diff(a, %Other{x: 1}) == :not_comparable
    end

    test "plain maps work too" do
      assert Diff.diff(%{a: 1, b: 2}, %{a: 1, b: 3}) == %{b: {:changed, 2, 3}}
    end
  end

  describe "apply/2" do
    test "applies a primitive change" do
      {:ok, a} = User.builder(%{name: "Alice", age: 30})
      patched = Diff.apply(a, %{age: {:changed, 30, 31}})

      assert patched.age == 31
      assert patched.name == "Alice"
    end

    test "applies a nested change" do
      {:ok, a} = User.builder(%{name: "Alice", address: %{city: "NYC", zip: "10001"}})

      patched = Diff.apply(a, %{address: %{city: {:changed, "NYC", "Chicago"}}})

      assert patched.address.city == "Chicago"
      assert patched.address.zip == "10001"
    end

    test "diff and apply round-trip" do
      {:ok, a} = User.builder(%{name: "Alice", age: 30})
      {:ok, b} = User.builder(%{name: "Bob", age: 35, role: "admin"})

      d = Diff.diff(a, b)
      reconstructed = Diff.apply(a, d)

      assert reconstructed == b
    end

    test "unknown keys in diff are silently ignored" do
      {:ok, a} = User.builder(%{name: "Alice"})
      patched = Diff.apply(a, %{nonexistent_field: {:changed, nil, "x"}})

      assert patched == a
    end
  end

  describe "equal?/2" do
    test "true for equal structs" do
      {:ok, a} = User.builder(%{name: "Alice", age: 30})
      {:ok, b} = User.builder(%{name: "Alice", age: 30})

      assert Diff.equal?(a, b)
    end

    test "false for differing structs" do
      {:ok, a} = User.builder(%{name: "Alice", age: 30})
      {:ok, b} = User.builder(%{name: "Bob", age: 30})

      refute Diff.equal?(a, b)
    end

    test "false for non-comparable" do
      {:ok, a} = User.builder(%{name: "Alice"})
      refute Diff.equal?(a, %Other2{x: 1})
    end
  end
end
