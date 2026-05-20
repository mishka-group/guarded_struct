defmodule GuardedStructTest.ConvertToAtomMapTest do
  use ExUnit.Case, async: true

  alias GuardedStruct.Derive.Parser

  describe "convert_to_atom_map/2 — no lookup (legacy 2-arity)" do
    test "converts known atom-name string keys" do
      assert %{name: "Alice", age: 30} =
               Parser.convert_to_atom_map(%{"name" => "Alice", "age" => 30})
    end

    test "leaves unknown string keys as strings (atom-DoS safety)" do
      unique = "_unique_garbage_key_for_test_#{System.unique_integer([:positive])}_"
      result = Parser.convert_to_atom_map(%{unique => "value"})
      assert %{^unique => "value"} = result
    end

    test "recurses into nested maps" do
      assert %{name: "Alice", profile: %{age: 30}} =
               Parser.convert_to_atom_map(%{"name" => "Alice", "profile" => %{"age" => 30}})
    end

    test "honors passthrough_keys — values stay untouched at any depth" do
      assert %{tags: %{"deep" => %{"nested" => 1}}} =
               Parser.convert_to_atom_map(
                 %{"tags" => %{"deep" => %{"nested" => 1}}},
                 [:tags]
               )
    end

    test "unwraps {:ok, map} input" do
      assert %{name: "Alice"} = Parser.convert_to_atom_map({:ok, %{"name" => "Alice"}})
    end

    test "passes {:error, _, _} input through unchanged" do
      err = {:error, :reason, "details"}
      assert ^err = Parser.convert_to_atom_map(err)
    end

    test "converts a struct by taking its map representation" do
      uri = URI.parse("https://example.com")
      result = Parser.convert_to_atom_map(uri)
      assert is_map(result)
      refute Map.has_key?(result, :__struct__)
      assert result.host == "example.com"
    end
  end

  describe "convert_to_atom_map/3 — with atom_lookup (the #6 compile-time fast path)" do
    test "uses lookup hit and bypasses String.to_existing_atom" do
      lookup = %{"name" => :name, "age" => :age}

      assert %{name: "Alice", age: 30} =
               Parser.convert_to_atom_map(%{"name" => "Alice", "age" => 30}, [], lookup)
    end

    test "lookup miss falls back to safe rescue (unknown stays string)" do
      lookup = %{"name" => :name}
      unique = "_garbage_lookup_miss_#{System.unique_integer([:positive])}_"
      result = Parser.convert_to_atom_map(%{"name" => "Alice", unique => "x"}, [], lookup)
      assert result[:name] == "Alice"
      assert result[unique] == "x"
    end

    test "empty lookup map still works (degrades to rescue path)" do
      assert %{name: "Alice"} =
               Parser.convert_to_atom_map(%{"name" => "Alice"}, [], %{})
    end

    test "nil lookup is equivalent to 2-arity behavior" do
      base = Parser.convert_to_atom_map(%{"name" => "Alice"})
      with_nil = Parser.convert_to_atom_map(%{"name" => "Alice"}, [], nil)
      assert base == with_nil
    end

    test "passthrough_keys still suppresses recursion when lookup is set" do
      lookup = %{"tags" => :tags}

      assert %{tags: %{"deep" => 1}} =
               Parser.convert_to_atom_map(
                 %{"tags" => %{"deep" => 1}},
                 [:tags],
                 lookup
               )
    end

    test "lookup matches by exact string — alias mismatches don't apply" do
      # If a lookup says "Name" -> :name, the key "name" misses the lookup
      # and falls back to rescue (string preserved if no atom exists).
      lookup = %{"Name" => :name}
      unique = "_no_atom_for_this_#{System.unique_integer([:positive])}_"
      result = Parser.convert_to_atom_map(%{unique => "x"}, [], lookup)
      assert %{^unique => "x"} = result
    end
  end
end
