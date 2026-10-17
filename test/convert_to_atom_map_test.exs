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

  describe "convert_to_atom_map/4 — structs are kept" do
    test "a nested struct is not turned into a map" do
      time = ~T[10:00:00]
      uri = URI.parse("https://example.com/x")

      assert %{t: ^time, u: ^uri} =
               Parser.convert_to_atom_map(%{"t" => time, "u" => uri})
    end

    test "Date, DateTime and NaiveDateTime stay as they were" do
      date = ~D[2026-01-02]
      datetime = ~U[2026-01-02 03:04:05Z]
      naive = ~N[2026-01-02 03:04:05]

      assert %{d: ^date, dt: ^datetime, n: ^naive} =
               Parser.convert_to_atom_map(%{"d" => date, "dt" => datetime, "n" => naive})
    end

    test "structs of other kinds stay as they were" do
      range = 1..5
      mapset = MapSet.new([1, 2])
      version = %Version{major: 1, minor: 2, patch: 3}

      assert %{r: ^range, m: ^mapset, v: ^version} =
               Parser.convert_to_atom_map(%{"r" => range, "m" => mapset, "v" => version})
    end

    test "structs inside a list and a deeper map stay as they were" do
      time = ~T[10:00:00]

      assert %{items: [^time, %{inner: ^time}]} =
               Parser.convert_to_atom_map(%{"items" => [time, %{"inner" => time}]})
    end

    test "the plain maps around a struct are still converted" do
      assert %{outer: %{inner: %Time{}}} =
               Parser.convert_to_atom_map(%{"outer" => %{"inner" => ~T[10:00:00]}})
    end

    test "a struct handed in as the whole input is still read as a map" do
      assert %{host: "example.com"} = Parser.convert_to_atom_map(URI.parse("https://example.com"))
    end
  end

  describe "convert_to_atom_map/4 — nested conversion specs" do
    @unique "_nested_spec_garbage_#{System.unique_integer([:positive])}_"

    test "the function answers for the converted key of a nested map" do
      nested = fn
        :profile -> %{passthrough: [:meta], nested: fn _key -> nil end}
        _key -> nil
      end

      input = %{"profile" => %{"meta" => %{"Role" => "x", @unique => 1}, "name" => "a"}}

      assert %{profile: %{meta: %{"Role" => "x", @unique => 1}, name: "a"}} =
               Parser.convert_to_atom_map(input, [], nil, nested)
    end

    test "a key the function does not know converts all the way down" do
      nested = fn _key -> nil end

      assert %{profile: %{meta: %{name: "a"}}} =
               Parser.convert_to_atom_map(
                 %{"profile" => %{"meta" => %{"name" => "a"}}},
                 [],
                 nil,
                 nested
               )
    end

    test "every map of a list is converted with the spec of its key" do
      nested = fn
        :items -> %{passthrough: [:meta], nested: fn _key -> nil end}
        _key -> nil
      end

      input = %{"items" => [%{"meta" => %{"A" => 1}}, %{"meta" => %{"B" => 2}}]}

      assert %{items: [%{meta: %{"A" => 1}}, %{meta: %{"B" => 2}}]} =
               Parser.convert_to_atom_map(input, [], nil, nested)
    end

    test "a spec nests: its own function answers for the keys below" do
      nested = fn
        :a ->
          %{passthrough: [], nested: fn :b -> %{passthrough: [:c], nested: fn _ -> nil end} end}

        _key ->
          nil
      end

      input = %{"a" => %{"b" => %{"c" => %{"Keep" => 1}, "d" => %{"name" => 2}}}}

      assert %{a: %{b: %{c: %{"Keep" => 1}, d: %{name: 2}}}} =
               Parser.convert_to_atom_map(input, [], nil, nested)
    end

    test "nil as the function is the plain conversion" do
      assert Parser.convert_to_atom_map(%{"a" => %{"b" => 1}}, [], nil, nil) ==
               Parser.convert_to_atom_map(%{"a" => %{"b" => 1}})
    end
  end
end
