defmodule GuardedStructTest.OpParamValidatorTest do
  use ExUnit.Case, async: true

  alias GuardedStruct.Derive.OpParamValidator

  describe "validate!/3 — valid params pass through unchanged" do
    test "max_len with positive integer" do
      ops = %{validate: [{:max_len, 10}]}
      assert ^ops = OpParamValidator.validate!(ops, :name, FakeMod)
    end

    test "min_len with non-negative integer" do
      assert %{validate: [{:min_len, 0}]} =
               OpParamValidator.validate!(%{validate: [{:min_len, 0}]}, :name, FakeMod)
    end

    test "regex with charlist" do
      assert %{validate: [{:regex, ~c"^[a-z]+$"}]} =
               OpParamValidator.validate!(%{validate: [{:regex, ~c"^[a-z]+$"}]}, :name, FakeMod)
    end

    test "enum with String[…] form" do
      assert %{validate: [{:enum, "String[a::b::c]"}]} =
               OpParamValidator.validate!(
                 %{validate: [{:enum, "String[a::b::c]"}]},
                 :name,
                 FakeMod
               )
    end

    test "enum with pre-evaluated list (from OpEvaluator)" do
      assert %{validate: [{:enum, ["a", "b"]}]} =
               OpParamValidator.validate!(%{validate: [{:enum, ["a", "b"]}]}, :name, FakeMod)
    end

    test "equal with Integer::value" do
      assert %{validate: [{:equal, "Integer::42"}]} =
               OpParamValidator.validate!(
                 %{validate: [{:equal, "Integer::42"}]},
                 :name,
                 FakeMod
               )
    end

    test "record with atom tag" do
      assert %{validate: [{:record, :user}]} =
               OpParamValidator.validate!(%{validate: [{:record, :user}]}, :name, FakeMod)
    end

    test "custom with module-list + fun atom" do
      assert %{validate: [{:custom, {[:Foo, :Bar], :ok?}}]} =
               OpParamValidator.validate!(
                 %{validate: [{:custom, {[:Foo, :Bar], :ok?}}]},
                 :name,
                 FakeMod
               )
    end

    test "tag sanitizer with atom sub-op" do
      assert %{sanitize: [{:tag, :strip_tags}]} =
               OpParamValidator.validate!(%{sanitize: [{:tag, :strip_tags}]}, :name, FakeMod)
    end

    test "either: recurses into inner ops" do
      ops = %{validate: [%{either: [:string, {:max_len, 10}]}]}
      assert ^ops = OpParamValidator.validate!(ops, :name, FakeMod)
    end

    test "bare atoms (e.g. :string, :not_empty) pass through" do
      assert %{validate: [:string, :not_empty]} =
               OpParamValidator.validate!(%{validate: [:string, :not_empty]}, :name, FakeMod)
    end

    test "nil ops returns nil" do
      assert nil == OpParamValidator.validate!(nil, :name, FakeMod)
    end
  end

  describe "validate!/3 — bad params raise" do
    test "max_len with a string raises" do
      assert_raise Spark.Error.DslError, ~r/invalid parameter for `max_len`/, fn ->
        OpParamValidator.validate!(%{validate: [{:max_len, "foo"}]}, :name, FakeMod)
      end
    end

    test "max_len with a negative integer raises" do
      assert_raise Spark.Error.DslError, ~r/non-negative integer/, fn ->
        OpParamValidator.validate!(%{validate: [{:max_len, -5}]}, :name, FakeMod)
      end
    end

    test "min_len with non-integer raises" do
      assert_raise Spark.Error.DslError, ~r/non-negative integer/, fn ->
        OpParamValidator.validate!(%{validate: [{:min_len, "0"}]}, :name, FakeMod)
      end
    end

    test "tell with non-integer raises" do
      assert_raise Spark.Error.DslError, ~r/integer.*country code/, fn ->
        OpParamValidator.validate!(%{validate: [{:tell, "98"}]}, :name, FakeMod)
      end
    end

    test "regex with integer raises" do
      assert_raise Spark.Error.DslError, ~r/charlist or string/, fn ->
        OpParamValidator.validate!(%{validate: [{:regex, 42}]}, :name, FakeMod)
      end
    end

    test "enum with bare integer (not Type[…] or list) raises" do
      assert_raise Spark.Error.DslError, ~r/Type\[/, fn ->
        OpParamValidator.validate!(%{validate: [{:enum, 42}]}, :name, FakeMod)
      end
    end

    test "enum with non-prefixed string raises" do
      assert_raise Spark.Error.DslError, fn ->
        OpParamValidator.validate!(%{validate: [{:enum, "bare"}]}, :name, FakeMod)
      end
    end

    test "equal with non-prefixed string raises" do
      assert_raise Spark.Error.DslError, ~r/Type::value/, fn ->
        OpParamValidator.validate!(%{validate: [{:equal, "bare"}]}, :name, FakeMod)
      end
    end

    test "record with integer tag raises" do
      assert_raise Spark.Error.DslError, ~r/atom or string tag/, fn ->
        OpParamValidator.validate!(%{validate: [{:record, 42}]}, :name, FakeMod)
      end
    end

    test "tag sanitizer with integer raises" do
      assert_raise Spark.Error.DslError, ~r/atom.*or string/, fn ->
        OpParamValidator.validate!(%{sanitize: [{:tag, 42}]}, :name, FakeMod)
      end
    end

    test "either: with bad inner op raises" do
      assert_raise Spark.Error.DslError, ~r/max_len/, fn ->
        OpParamValidator.validate!(
          %{validate: [%{either: [:string, {:max_len, "bad"}]}]},
          :name,
          FakeMod
        )
      end
    end
  end

  describe "validate!/3 — optional/each combinator inner ops" do
    test "optional with registered atom inner passes" do
      ops = %{validate: [{:optional, [:string]}]}
      assert ^ops = OpParamValidator.validate!(ops, :name, FakeMod)
    end

    test "optional with parameterised tuple inner passes and cascades param-shape check" do
      ops = %{validate: [{:optional, [:string, {:max_len, 20}]}]}
      assert ^ops = OpParamValidator.validate!(ops, :name, FakeMod)
    end

    test "optional map form with mixed atom and tuple inners passes" do
      ops = %{validate: [%{optional: [:string, {:max_len, 20}]}]}
      assert ^ops = OpParamValidator.validate!(ops, :name, FakeMod)
    end

    test "optional with unknown atom inner raises with op name" do
      assert_raise Spark.Error.DslError, ~r/unknown validate op :strng inside `optional`/, fn ->
        OpParamValidator.validate!(%{validate: [{:optional, [:strng]}]}, :name, FakeMod)
      end
    end

    test "optional with bad param inside known tuple inner raises (cascade)" do
      assert_raise Spark.Error.DslError, ~r/invalid parameter for `max_len`/, fn ->
        OpParamValidator.validate!(
          %{validate: [{:optional, [:string, {:max_len, "bad"}]}]},
          :name,
          FakeMod
        )
      end
    end

    test "each (validate side) with registered atom inner passes" do
      ops = %{validate: [{:each, [:string]}]}
      assert ^ops = OpParamValidator.validate!(ops, :name, FakeMod)
    end

    test "each (validate side) with parameterised tuple inner passes and cascades" do
      ops = %{validate: [{:each, [:string, {:max_len, 200}]}]}
      assert ^ops = OpParamValidator.validate!(ops, :name, FakeMod)
    end

    test "each (validate side) with unknown atom inner raises" do
      assert_raise Spark.Error.DslError, ~r/unknown validate op :foo inside `each`/, fn ->
        OpParamValidator.validate!(%{validate: [{:each, [:foo]}]}, :name, FakeMod)
      end
    end

    test "each (validate side) with bad param inside known tuple inner raises (cascade)" do
      assert_raise Spark.Error.DslError, ~r/invalid parameter for `max_len`/, fn ->
        OpParamValidator.validate!(
          %{validate: [{:each, [:string, {:max_len, "bad"}]}]},
          :name,
          FakeMod
        )
      end
    end

    test "each (sanitize side) with registered atom inners passes" do
      ops = %{sanitize: [{:each, [:trim, :downcase]}]}
      assert ^ops = OpParamValidator.validate!(ops, :name, FakeMod)
    end

    test "each (sanitize side) with unknown atom inner raises" do
      assert_raise Spark.Error.DslError, ~r/unknown sanitize op :nope inside `each`/, fn ->
        OpParamValidator.validate!(%{sanitize: [{:each, [:nope]}]}, :name, FakeMod)
      end
    end

    test "each (sanitize side) with parameterised tuple inner passes and cascades" do
      ops = %{sanitize: [{:each, [:trim, {:clamp, [0, 100]}]}]}
      assert ^ops = OpParamValidator.validate!(ops, :name, FakeMod)
    end

    test "each (sanitize side) with bad param inside known tuple inner raises (cascade)" do
      assert_raise Spark.Error.DslError, ~r/invalid parameter for `clamp`/, fn ->
        OpParamValidator.validate!(
          %{sanitize: [{:each, [:trim, {:clamp, [10, 0]}]}]},
          :name,
          FakeMod
        )
      end
    end
  end
end
