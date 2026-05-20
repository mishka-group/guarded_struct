defmodule GuardedStructTest.CombinatorNestingTest do
  use ExUnit.Case, async: true

  alias GuardedStruct.Derive.{OpParamValidator, ValidationDerive, SanitizerDerive}

  # ──────────────────────────────────────────────────────────────────
  # Runtime — validate side, nested combinators
  # Pattern checked at each depth: an inner op that ACCEPTS a sample
  # input returns the input; one that REJECTS produces an :error tuple.
  # ──────────────────────────────────────────────────────────────────

  describe "validate runtime — 2-level nests" do
    test "each[either]: every element matches one of N types" do
      op = %{each: [%{either: [:string, :integer]}]}
      assert ["a", 2, "c"] == ValidationDerive.validate(op, ["a", 2, "c"], :xs)
      assert {:error, _, :each, _} = ValidationDerive.validate(op, ["a", 2, :bad_atom], :xs)
    end

    test "each[optional]: every element may be nil" do
      op = %{each: [%{optional: [:string]}]}
      assert ["a", nil, "c"] == ValidationDerive.validate(op, ["a", nil, "c"], :xs)
      assert {:error, _, :each, _} = ValidationDerive.validate(op, ["a", 42, nil], :xs)
    end

    test "optional[either]: nil or one of N" do
      op = %{optional: [%{either: [:string, :integer]}]}
      assert nil == ValidationDerive.validate(op, nil, :x)
      assert "ok" == ValidationDerive.validate(op, "ok", :x)
      assert 7 == ValidationDerive.validate(op, 7, :x)
      assert {:error, _, :either, _} = ValidationDerive.validate(op, %{}, :x)
    end

    test "either[each]: either-a-list-of-strings or an integer" do
      op = %{either: [%{each: [:string]}, :integer]}
      assert ["a", "b"] == ValidationDerive.validate(op, ["a", "b"], :x)
      assert 5 == ValidationDerive.validate(op, 5, :x)
      assert {:error, _, :either, _} = ValidationDerive.validate(op, [1, 2], :x)
    end
  end

  describe "validate runtime — 3-level nests" do
    test "each[optional[either]]: list of (nil-or-one-of)" do
      op = %{each: [%{optional: [%{either: [:string, :integer]}]}]}
      assert ["a", nil, 2, "c"] == ValidationDerive.validate(op, ["a", nil, 2, "c"], :xs)
      assert {:error, _, :each, _} = ValidationDerive.validate(op, ["a", :bad], :xs)
    end

    test "optional[each[either]]: nil-or-(list-of-one-of)" do
      op = %{optional: [%{each: [%{either: [:string, :integer]}]}]}
      assert nil == ValidationDerive.validate(op, nil, :x)
      assert ["a", 2] == ValidationDerive.validate(op, ["a", 2], :x)
      assert {:error, _, :each, _} = ValidationDerive.validate(op, ["a", :bad], :x)
    end

    test "either[each[optional]]: int OR list-of-(nil-or-string)" do
      op = %{either: [:integer, %{each: [%{optional: [:string]}]}]}
      assert 5 == ValidationDerive.validate(op, 5, :x)
      assert ["a", nil, "c"] == ValidationDerive.validate(op, ["a", nil, "c"], :x)
      assert {:error, _, :either, _} = ValidationDerive.validate(op, [1, 2], :x)
    end
  end

  describe "validate runtime — 5-level nests" do
    # each[each[optional[either[each]]]]: matrix of (nil-or-list-of-string-or-int)
    test "matrix-of-cells where each cell is nil OR a list of strings/integers" do
      op = %{
        each: [
          %{
            each: [
              %{
                optional: [
                  %{either: [%{each: [:string]}, %{each: [:integer]}]}
                ]
              }
            ]
          }
        ]
      }

      good = [
        [["a", "b"], nil, [1, 2]],
        [nil, ["x"]]
      ]

      assert good == ValidationDerive.validate(op, good, :grid)

      # Cell contains mixed types -> each-of-strings fails AND each-of-integers fails -> either fails.
      bad = [[["a", 1], nil]]
      assert {:error, _, :each, _} = ValidationDerive.validate(op, bad, :grid)
    end
  end

  describe "validate runtime — 7-level nests" do
    # each → optional → either → each → optional → either → string
    # i.e. list of (nil-or-(list-or-X)) where the leaf is nil-or-(string-or-integer)
    test "depth-7 alternation of each/optional/either bottoms out at string|integer" do
      op = %{
        each: [
          %{
            optional: [
              %{
                either: [
                  %{
                    each: [
                      %{
                        optional: [
                          %{either: [:string, :integer]}
                        ]
                      }
                    ]
                  },
                  :string
                ]
              }
            ]
          }
        ]
      }

      good = [
        nil,
        "leaf-string-via-either-second-arm",
        ["x", nil, 2],
        [nil, nil]
      ]

      assert good == ValidationDerive.validate(op, good, :deep)

      # An inner list that contains a bad atom: every either arm fails.
      bad = [["ok", :nope]]
      assert {:error, _, :each, _} = ValidationDerive.validate(op, bad, :deep)
    end
  end

  # ──────────────────────────────────────────────────────────────────
  # Runtime — sanitize side, nested :each
  # ──────────────────────────────────────────────────────────────────

  describe "sanitize runtime — nested each" do
    test "each[each[trim, downcase]]: nested-list cell cleanup" do
      op = %{each: [%{each: [:trim, :downcase]}]}
      input = [["  A  ", "  B  "], ["  C  "]]
      assert [["a", "b"], ["c"]] == SanitizerDerive.sanitize(input, op)
    end

    test "each[each[each[trim]]]: 3-deep trim" do
      op = %{each: [%{each: [%{each: [:trim]}]}]}
      input = [[["  hi  "], ["  there  "]], [["  ok  "]]]
      assert [[["hi"], ["there"]], [["ok"]]] == SanitizerDerive.sanitize(input, op)
    end
  end

  # ──────────────────────────────────────────────────────────────────
  # Compile-time — OpParamValidator walks combinator inners recursively
  # ──────────────────────────────────────────────────────────────────

  describe "OpParamValidator — nested combinator inner ops are checked recursively" do
    test "3-deep all-valid passes" do
      ops = %{validate: [%{each: [%{optional: [%{either: [:string, :integer]}]}]}]}
      assert ^ops = OpParamValidator.validate!(ops, :name, FakeMod)
    end

    test "5-deep all-valid passes" do
      ops = %{
        validate: [
          %{
            each: [
              %{
                optional: [
                  %{either: [%{each: [:string]}, %{each: [:integer]}]}
                ]
              }
            ]
          }
        ]
      }

      assert ^ops = OpParamValidator.validate!(ops, :name, FakeMod)
    end

    test "7-deep all-valid passes" do
      ops = %{
        validate: [
          %{
            each: [
              %{
                optional: [
                  %{
                    either: [
                      %{each: [%{optional: [%{either: [:string, :integer]}]}]},
                      :string
                    ]
                  }
                ]
              }
            ]
          }
        ]
      }

      assert ^ops = OpParamValidator.validate!(ops, :name, FakeMod)
    end

    test "bad param shape deep inside an each→optional→either chain raises with the bad op name" do
      ops = %{
        validate: [
          %{each: [%{optional: [%{either: [:string, {:max_len, "bad"}]}]}]}
        ]
      }

      assert_raise Spark.Error.DslError, ~r/invalid parameter for `max_len`/, fn ->
        OpParamValidator.validate!(ops, :name, FakeMod)
      end
    end

    test "unknown op deep inside an each→optional chain raises with its name" do
      ops = %{validate: [%{each: [%{optional: [:strng]}]}]}

      assert_raise Spark.Error.DslError, ~r/unknown validate op :strng/, fn ->
        OpParamValidator.validate!(ops, :name, FakeMod)
      end
    end

    test "sanitize side: 3-deep each-each-each passes" do
      ops = %{sanitize: [%{each: [%{each: [%{each: [:trim, :downcase]}]}]}]}
      assert ^ops = OpParamValidator.validate!(ops, :name, FakeMod)
    end

    test "sanitize side: bad inner deep inside each chain raises" do
      ops = %{sanitize: [%{each: [%{each: [:not_a_sanitize_op]}]}]}

      assert_raise Spark.Error.DslError, ~r/unknown sanitize op :not_a_sanitize_op/, fn ->
        OpParamValidator.validate!(ops, :name, FakeMod)
      end
    end
  end
end
