defmodule GuardedStructTest.PatternMapTest do
  use ExUnit.Case, async: true

  alias GuardedStructTest.Fixtures.PatternMap.{
    Shard,
    ShardsMap,
    Plan,
    MultiPattern,
    HeadersMap
  }

  describe "standalone pattern-map struct" do
    test "builds a top-level flat map of validated structs" do
      assert {:ok,
              %{
                "shard_1" => %Shard{node: "10.0.0.1"},
                "shard_2" => %Shard{node: "10.0.0.2"}
              }} =
               ShardsMap.builder(%{
                 "shard_1" => %{node: "10.0.0.1"},
                 "shard_2" => %{node: "10.0.0.2"}
               })
    end

    test "result is a plain map, not a struct" do
      {:ok, result} = ShardsMap.builder(%{"shard_1" => %{node: "10.0.0.1"}})

      refute Map.has_key?(result, :__struct__)
      assert is_map(result)
    end

    test "%ShardsMap{} struct literal does not exist" do
      refute function_exported?(ShardsMap, :__struct__, 0)
    end

    test "rejects keys that don't match the regex pattern" do
      {:error, errs} =
        ShardsMap.builder(%{
          "shard_1" => %{node: "10.0.0.1"},
          "bad_key" => %{node: "10.0.0.2"}
        })

      assert Enum.any?(errs, &match?(%{key: "bad_key", action: :key_pattern}, &1))
    end

    test "fails whole-map derive when input is empty (validate(not_empty))" do
      {:error, errs} = ShardsMap.builder(%{})

      assert Enum.any?(errs, &match?(%{action: :not_empty}, &1))
    end

    test "rejects non-map input" do
      assert {:error, [%{action: :bad_parameters}]} = ShardsMap.builder("not a map")
      assert {:error, [%{action: :bad_parameters}]} = ShardsMap.builder([1, 2, 3])
      assert {:error, [%{action: :bad_parameters}]} = ShardsMap.builder(nil)
    end

    test "rejects the keyed and typed tuple forms of builder/1" do
      attrs = %{"shard_1" => %{node: "10.0.0.1"}}

      assert {:error, [%{action: :bad_parameters}]} = ShardsMap.builder({:root, attrs})
      assert {:error, [%{action: :bad_parameters}]} = ShardsMap.builder({:root, attrs, :add})
    end

    test "per-value validation runs through the target struct" do
      {:error, errs} = ShardsMap.builder(%{"shard_1" => %{node: "not-an-ip"}})

      assert Enum.any?(errs, fn err ->
               err[:key] == "shard_1" and err[:action] == :ipv4
             end)
    end

    test "preserves string keys (atoms not created from input)" do
      {:ok, result} = ShardsMap.builder(%{"shard_999" => %{node: "1.1.1.1"}})

      assert Map.has_key?(result, "shard_999")
      refute Map.has_key?(result, :shard_999)
    end

    test "atom-attack: huge unique keys don't create new atoms" do
      input =
        for i <- 1..1000, into: %{} do
          {"shard_#{i}", %{node: "10.0.0.#{rem(i, 255)}"}}
        end

      {:ok, result} = ShardsMap.builder(input)

      assert map_size(result) == 1000
      assert Enum.all?(Map.keys(result), &is_binary/1)
    end

    test "rejects when ANY single key fails its pattern" do
      {:error, errs} =
        ShardsMap.builder(%{
          "shard_1" => %{node: "10.0.0.1"},
          "shard_2" => %{node: "10.0.0.2"},
          "not_a_shard" => %{node: "10.0.0.3"}
        })

      assert Enum.any?(errs, &(&1[:key] == "not_a_shard"))
    end

    test "missing required field on inner struct surfaces as a per-key error" do
      {:error, errs} = ShardsMap.builder(%{"shard_1" => %{}})

      assert Enum.any?(errs, &(&1[:key] == "shard_1"))
    end

    test "accepts atom keys at input but normalises to strings on output" do
      {:ok, result} = ShardsMap.builder(%{shard_5: %{node: "10.0.0.5"}})

      assert Map.has_key?(result, "shard_5")
    end
  end

  describe "introspection" do
    test "keys/0 returns []" do
      assert ShardsMap.keys() == []
    end

    test "enforce_keys/0 returns []" do
      assert ShardsMap.enforce_keys() == []
    end

    test "__information__/0 marks the shape as :pattern_map" do
      info = ShardsMap.__information__()

      assert info.shape == :pattern_map
      assert info.key == :pattern
      assert info.keys == []
      assert is_list(info.patterns)
      assert Enum.all?(info.patterns, &is_struct(&1, Regex))
    end

    test "__fields__/0 returns pattern_field metadata" do
      [meta] = ShardsMap.__fields__()

      assert meta.kind == :pattern_field
      assert is_struct(meta.pattern, Regex)
      assert meta.struct == Shard
    end
  end

  describe "nested under a regular struct via struct: option" do
    test "Plan.builder produces a struct with the validated map at :shards_map" do
      assert {:ok,
              %Plan{
                status: "active",
                shards_map: %{
                  "shard_1" => %Shard{node: "10.0.0.1"},
                  "shard_2" => %Shard{node: "10.0.0.2"}
                }
              }} =
               Plan.builder(%{
                 status: "active",
                 shards_map: %{
                   "shard_1" => %{node: "10.0.0.1"},
                   "shard_2" => %{node: "10.0.0.2"}
                 }
               })
    end

    test "errors inside the map propagate through the parent struct" do
      {:error, errs} =
        Plan.builder(%{
          status: "active",
          shards_map: %{"shard_1" => %{node: "not-an-ip"}}
        })

      assert is_list(errs) and errs != []
    end
  end

  describe "multiple regex patterns coexist" do
    test "different keys match different patterns" do
      assert {:ok,
              %{
                "shard_1" => %Shard{node: "10.0.0.1"},
                "backup_99" => %Shard{node: "10.0.0.2"}
              }} =
               MultiPattern.builder(%{
                 "shard_1" => %{node: "10.0.0.1"},
                 "backup_99" => %{node: "10.0.0.2"}
               })
    end

    test "key matching no pattern still errors" do
      {:error, errs} =
        MultiPattern.builder(%{
          "shard_1" => %{node: "10.0.0.1"},
          "random" => %{node: "10.0.0.2"}
        })

      assert Enum.any?(errs, &(&1[:key] == "random"))
    end
  end

  describe "compile-time mixing detection" do
    test "mixing atom and regex fields raises Spark.Error.DslError" do
      src = """
      defmodule BadMixed#{:erlang.unique_integer([:positive])} do
        use GuardedStruct
        guardedstruct do
          field(:name, String.t())
          field(~r/^tag_\\d+$/, String.t())
        end
      end
      """

      assert_raise Spark.Error.DslError,
                   ~r/cannot mix atom-keyed and regex-keyed/,
                   fn -> Code.compile_string(src) end
    end
  end

  describe "primitive-value pattern map" do
    test "accepts entries with valid header-like keys" do
      {:ok, result} =
        HeadersMap.builder(%{
          "X-API-Key" => "secret",
          "X-Tenant-Id" => "abc-123"
        })

      assert result == %{"X-API-Key" => "secret", "X-Tenant-Id" => "abc-123"}
    end

    test "rejects keys not matching the header convention" do
      {:error, errs} =
        HeadersMap.builder(%{
          "X-API-Key" => "ok",
          "lowercase-bad" => "no"
        })

      assert Enum.any?(errs, &(&1[:key] == "lowercase-bad"))
    end
  end

  describe "error shape of a pattern-keyed map" do
    defmodule Checks do
      def check(key, "bad"), do: {:error, key, "#{key} is bad"}
      def check(_key, "shout"), do: {:ok, "SHOUT"}
      def check(key, "short"), do: {:error, "#{key} is short"}
      def check(key, value), do: {:ok, key, value}
    end

    defmodule WithValidator do
      use GuardedStruct

      guardedstruct do
        field(~r/^k_\d+$/, String.t(), validator: {Checks, :check})
      end
    end

    test "a validator error carries the key, the field, the action and the message" do
      assert {:error, [error]} = WithValidator.builder(%{"k_1" => "bad"})

      assert error == %{
               field: :__map__,
               key: "k_1",
               action: :validator,
               message: "k_1 is bad"
             }
    end

    test "the {:error, message} return of a validator has the same shape" do
      assert {:error, [error]} = WithValidator.builder(%{"k_2" => "short"})

      assert error == %{
               field: :__map__,
               key: "k_2",
               action: :validator,
               message: "k_2 is short"
             }
    end

    test "one error per failing key" do
      assert {:error, errors} =
               WithValidator.builder(%{"k_1" => "bad", "k_2" => "ok", "k_3" => "short"})

      assert errors |> Enum.map(& &1.key) |> Enum.sort() == ["k_1", "k_3"]
    end

    test "a validator that passes the value on keeps it" do
      assert {:ok, %{"k_1" => "ok", "k_2" => "SHOUT"}} =
               WithValidator.builder(%{"k_1" => "ok", "k_2" => "shout"})
    end

    test "every error the module returns has a :field, an :action and a :message" do
      {:error, errors} =
        WithValidator.builder(%{"k_1" => "bad", "k_2" => "short", "nope" => "x"})

      assert length(errors) == 3

      for error <- errors do
        assert %{field: field, action: action, message: message} = error
        assert is_atom(field)
        assert is_atom(action)
        assert is_binary(message)
      end
    end

    test "an unmatched key and a failing validator share the field" do
      {:error, errors} = WithValidator.builder(%{"k_1" => "bad", "nope" => "x"})

      assert [%{field: :__map__}, %{field: :__map__}] = errors
      assert Enum.any?(errors, &match?(%{key: "nope", action: :key_pattern}, &1))
      assert Enum.any?(errors, &match?(%{key: "k_1", action: :validator}, &1))
    end

    test "an error from a struct: value keeps its own field and gets the key" do
      {:error, errors} = ShardsMap.builder(%{"shard_1" => %{node: "not-an-ip"}})

      assert Enum.all?(errors, &match?(%{key: "shard_1", field: :node}, &1))
    end

    test "the whole-map derive error names the map as its field" do
      assert {:error, [%{field: :__map__, action: :not_empty}]} = ShardsMap.builder(%{})
    end

    test "with error: true the exception carries the same list" do
      defmodule Raising do
        use GuardedStruct

        guardedstruct error: true do
          field(~r/^k_\d+$/, String.t(), validator: {Checks, :check})
        end
      end

      error = assert_raise Raising.Error, fn -> Raising.builder(%{"k_1" => "bad"}, true) end
      assert [%{field: :__map__, key: "k_1", action: :validator}] = error.errors
    end
  end
end
