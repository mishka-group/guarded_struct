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
      assert_raise Spark.Error.DslError, ~r/charlist, string, or compiled Regex/, fn ->
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

  describe "validate!/3 — operands that could not be parsed" do
    test "an invalid operand at the top of a group raises with its source" do
      assert_raise Spark.Error.DslError,
                   ~r/could not parse the operand `max_len = foo\(\)`/,
                   fn ->
                     OpParamValidator.validate!(
                       %{validate: [{:invalid_operand, "max_len = foo()"}]},
                       :name,
                       FakeMod
                     )
                   end
    end

    test "on the sanitize side" do
      assert_raise Spark.Error.DslError, ~r/could not parse the operand `5`/, fn ->
        OpParamValidator.validate!(%{sanitize: [{:invalid_operand, "5"}]}, :name, FakeMod)
      end
    end

    test "inside either=[...]" do
      ops = %{validate: [%{either: [:string, {:invalid_operand, "x()"}]}]}

      assert_raise Spark.Error.DslError, ~r/could not parse the operand `x\(\)`/, fn ->
        OpParamValidator.validate!(ops, :name, FakeMod)
      end
    end

    test "inside each=[...] and optional=[...]" do
      assert_raise Spark.Error.DslError, ~r/could not parse the operand/, fn ->
        OpParamValidator.validate!(
          %{validate: [{:each, [{:invalid_operand, "x()"}]}]},
          :name,
          FakeMod
        )
      end

      assert_raise Spark.Error.DslError, ~r/could not parse the operand/, fn ->
        OpParamValidator.validate!(
          %{validate: [%{optional: [:string, {:invalid_operand, "x()"}]}]},
          :name,
          FakeMod
        )
      end
    end

    test "inside a parameterised op's own list" do
      assert_raise Spark.Error.DslError, ~r/could not parse the operand/, fn ->
        OpParamValidator.validate!(
          %{sanitize: [%{each: [%{each: [{:invalid_operand, "x()"}]}]}]},
          :name,
          FakeMod
        )
      end
    end

    test "the error names the field and the module" do
      error =
        assert_raise Spark.Error.DslError, fn ->
          OpParamValidator.validate!(%{validate: [{:invalid_operand, "x()"}]}, :age, FakeMod)
        end

      assert error.module == FakeMod
      assert error.path == [:guardedstruct, :field, :age, :derive]
      assert error.message =~ ":age"
    end

    test "a regex is not mistaken for an invalid operand" do
      ops = %{validate: [{:regex, ~r/^a$/}]}
      assert ^ops = OpParamValidator.validate!(ops, :name, FakeMod)
    end
  end

  describe "validate!/3 — number operands" do
    test "min_len with a negative integer raises" do
      assert_raise Spark.Error.DslError, ~r/`min_len`.*non-negative integer.*got -2/, fn ->
        OpParamValidator.validate!(%{validate: [{:min_len, -2}]}, :name, FakeMod)
      end
    end

    test "max_len with a float raises" do
      assert_raise Spark.Error.DslError, ~r/`max_len`.*non-negative integer.*got 1.5/, fn ->
        OpParamValidator.validate!(%{validate: [{:max_len, 1.5}]}, :name, FakeMod)
      end
    end

    test "a negative min_len inside each=[...] raises" do
      assert_raise Spark.Error.DslError, ~r/`min_len`/, fn ->
        OpParamValidator.validate!(%{validate: [{:each, [{:min_len, -1}]}]}, :name, FakeMod)
      end
    end

    test "clamp with negative bounds passes" do
      ops = %{sanitize: [{:clamp, [-10, 10]}]}
      assert ^ops = OpParamValidator.validate!(ops, :name, FakeMod)
    end

    test "clamp with its bounds reversed raises" do
      assert_raise Spark.Error.DslError, ~r/`clamp`/, fn ->
        OpParamValidator.validate!(%{sanitize: [{:clamp, [10, -10]}]}, :name, FakeMod)
      end
    end
  end

  describe "validate!/3 — Type::value and Type[...] operands that do not evaluate" do
    test "equal=Integer:: with a value that is not an integer" do
      assert_raise Spark.Error.DslError, ~r/`equal`.*Integer::42.*got "Integer::abc"/, fn ->
        OpParamValidator.validate!(%{validate: [{:equal, "Integer::abc"}]}, :name, FakeMod)
      end
    end

    test "equal=Float:: with a value that is not a float" do
      assert_raise Spark.Error.DslError, ~r/`equal`/, fn ->
        OpParamValidator.validate!(%{validate: [{:equal, "Float::x"}]}, :name, FakeMod)
      end
    end

    test "equal=Map:: and equal=Tuple:: with code that does not evaluate" do
      assert_raise Spark.Error.DslError, ~r/`equal`/, fn ->
        OpParamValidator.validate!(%{validate: [{:equal, "Map::%{a:"}]}, :name, FakeMod)
      end

      assert_raise Spark.Error.DslError, ~r/`equal`/, fn ->
        OpParamValidator.validate!(%{validate: [{:equal, "Tuple::{:a,"}]}, :name, FakeMod)
      end
    end

    test "well-formed typed values pass" do
      for value <- [
            "Integer::-42",
            "Float::1.5",
            "String::anything goes",
            "Atom::admin",
            "Map::%{a: 1}",
            "Tuple::{:a, 1}"
          ] do
        ops = %{validate: [{:equal, value}]}
        assert ^ops = OpParamValidator.validate!(ops, :name, FakeMod)
      end
    end

    test "enum=Integer[...] and enum=Float[...] with values that are not numbers" do
      assert_raise Spark.Error.DslError, ~r/`enum`/, fn ->
        OpParamValidator.validate!(%{validate: [{:enum, "Integer[a::b]"}]}, :name, FakeMod)
      end

      assert_raise Spark.Error.DslError, ~r/`enum`/, fn ->
        OpParamValidator.validate!(%{validate: [{:enum, "Float[a::b]"}]}, :name, FakeMod)
      end
    end

    test "enum=Map[...] and enum=Tuple[...] with code that does not evaluate" do
      assert_raise Spark.Error.DslError, ~r/`enum`/, fn ->
        OpParamValidator.validate!(%{validate: [{:enum, "Map[%{a:]"}]}, :name, FakeMod)
      end

      assert_raise Spark.Error.DslError, ~r/`enum`/, fn ->
        OpParamValidator.validate!(%{validate: [{:enum, "Tuple[{:a,]"}]}, :name, FakeMod)
      end
    end

    test "well-formed enum values pass" do
      for value <- ["Integer[1::2]", "Float[1.5::2.5]", "Map[%{a: 1}::%{b: 2}]", "Tuple[{:a, 1}]"] do
        ops = %{validate: [{:enum, value}]}
        assert ^ops = OpParamValidator.validate!(ops, :name, FakeMod)
      end
    end
  end

  describe "validate!/4 — extra ops inside each= / optional=" do
    test "an op outside the built-in set raises without extra ops" do
      assert_raise Spark.Error.DslError, ~r/unknown validate op :zz_custom inside `each`/, fn ->
        OpParamValidator.validate!(%{validate: [{:each, [:zz_custom]}]}, :name, FakeMod)
      end
    end

    test "the error points at Derive.Extension" do
      assert_raise Spark.Error.DslError, ~r/GuardedStruct\.Derive\.Extension/, fn ->
        OpParamValidator.validate!(%{validate: [{:each, [:zz_custom]}]}, :name, FakeMod)
      end
    end

    test "extra_validate lets each=[...] and optional=[...] use it" do
      each_ops = %{validate: [{:each, [:zz_custom]}]}
      optional_ops = %{validate: [%{optional: [:string, :zz_custom]}]}

      assert ^each_ops =
               OpParamValidator.validate!(each_ops, :name, FakeMod, extra_validate: [:zz_custom])

      assert ^optional_ops =
               OpParamValidator.validate!(optional_ops, :name, FakeMod,
                 extra_validate: [:zz_custom]
               )
    end

    test "extra_sanitize lets sanitize each=[...] use it" do
      ops = %{sanitize: [{:each, [:trim, :zz_shout]}]}

      assert ^ops = OpParamValidator.validate!(ops, :name, FakeMod, extra_sanitize: [:zz_shout])

      assert_raise Spark.Error.DslError, ~r/unknown sanitize op :zz_shout/, fn ->
        OpParamValidator.validate!(ops, :name, FakeMod, extra_validate: [:zz_shout])
      end
    end

    test "an extra op does not excuse another unknown one" do
      assert_raise Spark.Error.DslError, ~r/unknown validate op :strng/, fn ->
        OpParamValidator.validate!(%{validate: [{:each, [:zz_custom, :strng]}]}, :name, FakeMod,
          extra_validate: [:zz_custom]
        )
      end
    end

    test ":any accepts every inner op" do
      ops = %{validate: [{:each, [:whatever]}], sanitize: [{:each, [:whatever]}]}

      assert ^ops =
               OpParamValidator.validate!(ops, :name, FakeMod,
                 extra_validate: :any,
                 extra_sanitize: :any
               )
    end

    test "a function is only called when an inner op is not built in" do
      extra = fn ->
        send(self(), :extra_called)
        [:zz_custom]
      end

      OpParamValidator.validate!(%{validate: [{:each, [:string]}]}, :name, FakeMod,
        extra_validate: extra
      )

      refute_received :extra_called

      OpParamValidator.validate!(%{validate: [{:each, [:zz_custom]}]}, :name, FakeMod,
        extra_validate: extra
      )

      assert_received :extra_called
    end

    test "the param shape of an extra op's tuple is still checked" do
      assert_raise Spark.Error.DslError, ~r/invalid parameter for `max_len`/, fn ->
        OpParamValidator.validate!(
          %{validate: [{:each, [:zz_custom, {:max_len, "bad"}]}]},
          :name,
          FakeMod,
          extra_validate: [:zz_custom]
        )
      end
    end
  end
end
