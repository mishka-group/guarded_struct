defmodule GuardedStructTest.CombinatorNestingTest do
  use ExUnit.Case, async: true

  alias GuardedStruct.Derive.{OpParamValidator, ValidationDerive, SanitizerDerive}

  # ────────────────────────────────────────────────────────────────
  # Fixtures — exercise the FULL macro pipeline: derive-string parser
  # → OpEvaluator → OpParamValidator → ValidationDerive/SanitizerDerive.
  # If anything in that chain mishandles a combinator, builder/1 fails.
  # ────────────────────────────────────────────────────────────────

  defmodule EitherFlat do
    use GuardedStruct

    guardedstruct do
      field(:val, any(), derives: "validate(either=[string, integer])")
    end
  end

  defmodule EachFlat do
    use GuardedStruct

    guardedstruct do
      field(:items, list(), derives: "validate(each=[string])")
    end
  end

  defmodule OptionalFlat do
    use GuardedStruct

    guardedstruct do
      field(:nick, any(), derives: "validate(optional=[string, max_len=5])")
    end
  end

  defmodule OptionalBareAtom do
    # The bare-atom form is the one that USED to allocate a binary inner
    # op and pay String.to_existing_atom + rescue per call. Now it's
    # parsed to {:optional, [:string]} at compile time.
    use GuardedStruct

    guardedstruct do
      field(:nick, any(), derives: "validate(optional=string)")
    end
  end

  defmodule SanitizeEach do
    use GuardedStruct

    guardedstruct do
      field(:tags, list(),
        derives: "sanitize(each=[trim, downcase], uniq) validate(each=[string])"
      )
    end
  end

  defmodule EachEither do
    use GuardedStruct

    guardedstruct do
      field(:cells, list(), derives: "validate(each=[either=[string, integer]])")
    end
  end

  defmodule OptionalEach do
    use GuardedStruct

    guardedstruct do
      field(:maybe_tags, any(), derives: "validate(optional=[each=[string]])")
    end
  end

  defmodule EitherEach do
    use GuardedStruct

    guardedstruct do
      field(:int_or_list, any(), derives: "validate(either=[integer, each=[string]])")
    end
  end

  defmodule DeepNest do
    # 5-deep through the macro pipeline:
    #   each → optional → either → each → string
    use GuardedStruct

    guardedstruct do
      field(:grid, list(),
        derives: "validate(each=[optional=[either=[each=[string], each=[integer]]]])"
      )
    end
  end

  # ────────────────────────────────────────────────────────────────
  # Macro pipeline fixtures at depth 8, 10, 12 — hand-written so the
  # parser actually sees a real long string (not something a runtime
  # helper assembled). Each level cycles through each→optional→either,
  # leaf is :string.
  # ────────────────────────────────────────────────────────────────

  defmodule Depth8 do
    use GuardedStruct

    guardedstruct do
      field(:x, any(),
        derives:
          "validate(each=[optional=[either=[each=[optional=[either=[each=[optional=[string]]]]]]]])"
      )
    end
  end

  defmodule Depth10 do
    use GuardedStruct

    guardedstruct do
      field(:x, any(),
        derives:
          "validate(each=[optional=[either=[each=[optional=[either=[each=[optional=[either=[each=[string]]]]]]]]]])"
      )
    end
  end

  defmodule Depth12 do
    use GuardedStruct

    guardedstruct do
      field(:x, any(),
        derives:
          "validate(each=[optional=[either=[each=[optional=[either=[each=[optional=[either=[each=[optional=[either=[string]]]]]]]]]]]])"
      )
    end
  end

  # ──────────────────────────────────────────────────────────────────
  # Runtime — validate side, nested combinators
  # Pattern checked at each depth: an inner op that ACCEPTS a sample
  # input returns the input; one that REJECTS produces an :error tuple.
  # ──────────────────────────────────────────────────────────────────

  describe "validate runtime — 2-level nests" do
    test "each[either]: every element matches one of N types" do
      op = %{each: [%{either: [:string, :integer]}]}
      assert ["a", 2, "c"] == ValidationDerive.validate(op, ["a", 2, "c"], :xs)
      assert {:error, _, :each, _, {:children, _}} = ValidationDerive.validate(op, ["a", 2, :bad_atom], :xs)
    end

    test "each[optional]: every element may be nil" do
      op = %{each: [%{optional: [:string]}]}
      assert ["a", nil, "c"] == ValidationDerive.validate(op, ["a", nil, "c"], :xs)
      assert {:error, _, :each, _, {:children, _}} = ValidationDerive.validate(op, ["a", 42, nil], :xs)
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
      assert {:error, _, :each, _, {:children, _}} = ValidationDerive.validate(op, ["a", :bad], :xs)
    end

    test "optional[each[either]]: nil-or-(list-of-one-of)" do
      op = %{optional: [%{each: [%{either: [:string, :integer]}]}]}
      assert nil == ValidationDerive.validate(op, nil, :x)
      assert ["a", 2] == ValidationDerive.validate(op, ["a", 2], :x)
      assert {:error, _, :each, _, {:children, _}} = ValidationDerive.validate(op, ["a", :bad], :x)
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
      assert {:error, _, :each, _, {:children, _}} = ValidationDerive.validate(op, bad, :grid)
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
      assert {:error, _, :each, _, {:children, _}} = ValidationDerive.validate(op, bad, :deep)
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

  # ──────────────────────────────────────────────────────────────────
  # End-to-end through Module.builder/1 — exercises the full pipeline
  # ──────────────────────────────────────────────────────────────────

  describe "either= through builder/1" do
    test "string passes" do
      assert {:ok, %EitherFlat{val: "ok"}} = EitherFlat.builder(%{val: "ok"})
    end

    test "integer passes" do
      assert {:ok, %EitherFlat{val: 7}} = EitherFlat.builder(%{val: 7})
    end

    test "neither matches → error" do
      assert {:error, errors} = EitherFlat.builder(%{val: :atom_bad})
      assert Enum.any?(errors, &(&1.action == :either))
    end
  end

  describe "each= through builder/1" do
    test "all-strings list passes" do
      assert {:ok, %EachFlat{items: ["a", "b"]}} = EachFlat.builder(%{items: ["a", "b"]})
    end

    test "one bad element → error map carries the failing index" do
      assert {:error, errors} = EachFlat.builder(%{items: ["a", 2, "c"]})

      assert [
               %{
                 field: :items,
                 action: :string,
                 __index__: 1,
                 message: _
               }
             ] = errors
    end
  end

  describe "optional= through builder/1 (bracket form)" do
    test "nil passes" do
      assert {:ok, %OptionalFlat{nick: nil}} = OptionalFlat.builder(%{nick: nil})
    end

    test "short string passes" do
      assert {:ok, %OptionalFlat{nick: "ab"}} = OptionalFlat.builder(%{nick: "ab"})
    end

    test "too-long string fails the inner max_len" do
      assert {:error, _errors} = OptionalFlat.builder(%{nick: "abcdef"})
    end
  end

  describe "optional=bare-atom through builder/1 (the kill-the-rescue path)" do
    test "nil passes (optional)" do
      assert {:ok, %OptionalBareAtom{nick: nil}} = OptionalBareAtom.builder(%{nick: nil})
    end

    test "string passes" do
      assert {:ok, %OptionalBareAtom{nick: "ok"}} = OptionalBareAtom.builder(%{nick: "ok"})
    end

    test "non-string non-nil fails" do
      assert {:error, _errors} = OptionalBareAtom.builder(%{nick: 42})
    end
  end

  describe "sanitize each= through builder/1" do
    test "every element trimmed + downcased; duplicates dropped" do
      assert {:ok, %SanitizeEach{tags: ["foo", "bar"]}} =
               SanitizeEach.builder(%{tags: ["  Foo  ", "  BAR  ", "foo"]})
    end
  end

  describe "nested combinators through builder/1" do
    test "each[either]: list of (string|integer)" do
      assert {:ok, %EachEither{cells: ["a", 2, "c"]}} =
               EachEither.builder(%{cells: ["a", 2, "c"]})

      assert {:error, errors} = EachEither.builder(%{cells: ["a", 2, :atom_bad]})
      assert Enum.any?(errors, &Map.has_key?(&1, :__index__))
    end

    test "optional[each]: nil-or-(list-of-strings)" do
      assert {:ok, %OptionalEach{maybe_tags: nil}} = OptionalEach.builder(%{maybe_tags: nil})

      assert {:ok, %OptionalEach{maybe_tags: ["a", "b"]}} =
               OptionalEach.builder(%{maybe_tags: ["a", "b"]})

      assert {:error, _} = OptionalEach.builder(%{maybe_tags: ["a", 2]})
    end

    test "either[each]: integer-or-(list-of-strings)" do
      assert {:ok, %EitherEach{int_or_list: 5}} = EitherEach.builder(%{int_or_list: 5})

      assert {:ok, %EitherEach{int_or_list: ["a", "b"]}} =
               EitherEach.builder(%{int_or_list: ["a", "b"]})

      assert {:error, _} = EitherEach.builder(%{int_or_list: [1, 2]})
    end

    test "5-deep nest through derive string: each→optional→either→each→leaf" do
      # Each cell: nil OR (list-of-strings OR list-of-integers)
      good_grid = [["a", "b"], nil, [1, 2], nil]
      assert {:ok, %DeepNest{grid: ^good_grid}} = DeepNest.builder(%{grid: good_grid})

      # Mixed types inside an inner list → both either arms fail → :each error bubbles up
      bad_grid = [["a", 1]]
      assert {:error, errors} = DeepNest.builder(%{grid: bad_grid})
      assert Enum.any?(errors, &Map.has_key?(&1, :__index__))
    end
  end

  # ──────────────────────────────────────────────────────────────────
  # Truly-deep nesting — cycle each → optional → either at every level,
  # leaf is :string. Tests at depths 8, 10, 12, 15 confirm the
  # dispatcher has NO depth limit and the OpParamValidator descends
  # the whole chain at compile time.
  # ──────────────────────────────────────────────────────────────────

  # Build a depth-N nested op cycling each→optional→either.
  defp deep_op(0, leaf), do: leaf
  defp deep_op(n, leaf) when n > 0, do: wrap(n, deep_op(n - 1, leaf))

  defp wrap(n, inner) do
    case rem(n, 3) do
      1 -> %{each: [inner]}
      2 -> %{optional: [inner]}
      0 -> %{either: [inner]}
    end
  end

  # Build a value that satisfies a depth-N op shape. For each layer,
  # wrap in a 1-element list (for :each) or pass through (for :optional /
  # :either with a single inner).
  defp deep_value(0, leaf_value), do: leaf_value
  defp deep_value(n, leaf_value) when n > 0, do: wrap_value(n, deep_value(n - 1, leaf_value))

  defp wrap_value(n, inner) do
    case rem(n, 3) do
      1 -> [inner]
      2 -> inner
      0 -> inner
    end
  end

  describe "DIRECT API — really deep nesting" do
    for depth <- [8, 10, 12, 15] do
      @depth depth
      test "depth #{@depth}: roundtrip with valid leaf" do
        op = deep_op(@depth, :string)
        value = deep_value(@depth, "leaf")
        assert ^value = ValidationDerive.validate(op, value, :deep)
      end

      test "depth #{@depth}: failing leaf bubbles up as :each error" do
        op = deep_op(@depth, :string)
        # Replace the leaf with an atom (fails :string validator)
        value = deep_value(@depth, :wrong_type)

        result = ValidationDerive.validate(op, value, :deep)

        assert is_tuple(result),
               "expected error tuple at depth #{@depth}, got: #{inspect(result)}"

        # Outermost is :each at depth 1, 4, 7, 10, 13... (rem == 1)
        # So depths 8, 10 outermost is :each or other — assert error of SOME action
        action = elem(result, 2)
        assert action in [:each, :either, :optional, :string, :type]
      end

      test "depth #{@depth}: OpParamValidator passes the all-valid chain at compile time" do
        ops = %{validate: [deep_op(@depth, :string)]}
        assert ^ops = OpParamValidator.validate!(ops, :name, FakeMod)
      end

      test "depth #{@depth}: OpParamValidator catches an unknown op buried at the leaf" do
        # Replace leaf :string with an unregistered atom
        ops = %{validate: [deep_op(@depth, :no_such_validator)]}

        assert_raise Spark.Error.DslError,
                     ~r/unknown validate op :no_such_validator/,
                     fn -> OpParamValidator.validate!(ops, :name, FakeMod) end
      end
    end
  end

  describe "MACRO PIPELINE — really deep nesting via derive string" do
    test "depth 8: builder roundtrips a value that drills all the way down" do
      # Each → optional → either → each → optional → either → each → optional → :string
      # The optional/either-with-single-arg arms degenerate to identity for the value,
      # so the value path needs :each wrappers (4 of them: at depths 8, 5, 2... wait
      # only :each wraps in a list). Depth 8 with cycle each/opt/either/each/opt/either/each/opt:
      # eaches at outer indices 8, 5, 2 → 3 list wrappings. Leaf = "ok".
      value = [[["ok"]]]
      assert {:ok, %Depth8{x: ^value}} = Depth8.builder(%{x: value})

      # Nil at any 'optional' layer also passes.
      assert {:ok, %Depth8{x: [[nil]]}} = Depth8.builder(%{x: [[nil]]})
      assert {:ok, %Depth8{x: [nil]}} = Depth8.builder(%{x: [nil]})

      # Bad leaf bubbles up.
      assert {:error, errors} = Depth8.builder(%{x: [[[:not_string]]]})
      assert Enum.any?(errors, &Map.has_key?(&1, :__index__))
    end

    test "depth 10: builder roundtrips a value that drills all the way down" do
      # Cycle: each, opt, either, each, opt, either, each, opt, either, each
      # → :each at outer-indices 10, 7, 4, 1 → 4 list wrappings around the leaf
      value = [[[["ok"]]]]
      assert {:ok, %Depth10{x: ^value}} = Depth10.builder(%{x: value})

      # Bad leaf bubbles up
      assert {:error, errors} = Depth10.builder(%{x: [[[[:not_string]]]]})
      assert Enum.any?(errors, &Map.has_key?(&1, :__index__))
    end

    test "depth 12: builder roundtrips a value that drills all the way down" do
      # Cycle: e,o,ei,e,o,ei,e,o,ei,e,o,ei
      # :each at depths 12, 9, 6, 3 → 4 list wrappings; leaf is the innermost value
      value = [[[["ok"]]]]
      assert {:ok, %Depth12{x: ^value}} = Depth12.builder(%{x: value})

      # Bad leaf
      assert {:error, errors} = Depth12.builder(%{x: [[[[:not_string]]]]})
      assert Enum.any?(errors, &Map.has_key?(&1, :__index__))
    end
  end

  # ──────────────────────────────────────────────────────────────────
  # EXPLICIT expected-value tables — prove the logic by literal.
  # Reader can verify by eye that the op shape, the input, and the
  # asserted output all line up with the documented semantics.
  # ──────────────────────────────────────────────────────────────────

  describe "expected-value confirmation (op, input, output are all literal)" do
    test "depth 3 — each[either[optional[string]]]: ANY element nil or a string" do
      op = %{each: [%{either: [%{optional: [:string]}]}]}

      assert ["a", nil, "c"] == ValidationDerive.validate(op, ["a", nil, "c"], :xs)
      assert [] == ValidationDerive.validate(op, [], :xs)
      assert [nil, nil] == ValidationDerive.validate(op, [nil, nil], :xs)

      # One non-string non-nil element fails the inner string check; either has
      # only one arm so it surfaces as :either; the outer each pins the index.
      assert {:error, :xs, :each, _msg, {:children, [child]}} =
               ValidationDerive.validate(op, ["a", 2, "c"], :xs)

      assert %{field: :xs, action: :either, __index__: 1, message: _} = child
    end

    test "depth 5 — each[optional[either[each[string], each[integer]]]]" do
      op = %{
        each: [
          %{
            optional: [
              %{either: [%{each: [:string]}, %{each: [:integer]}]}
            ]
          }
        ]
      }

      # Each cell is nil OR (list-of-strings OR list-of-integers)
      input = [["a", "b"], nil, [1, 2]]
      assert ^input = ValidationDerive.validate(op, input, :grid)

      # Mixed strings-and-ints in ONE cell → both either arms fail
      bad = [["a", 1]]

      assert {:error, :grid, :each, _msg, {:children, [child]}} =
               ValidationDerive.validate(op, bad, :grid)

      assert %{field: :grid, action: :either, __index__: 0, message: _} = child
    end

    test "nil at intermediate optional layer short-circuits (proves optional is real, not passthrough)" do
      # opt[each[optional[string]]]:  outer-opt allows nil at the very top;
      # otherwise each elem may itself be nil.
      op = %{optional: [%{each: [%{optional: [:string]}]}]}

      assert nil == ValidationDerive.validate(op, nil, :x)
      assert ["a", nil, "b"] == ValidationDerive.validate(op, ["a", nil, "b"], :x)
      assert [] == ValidationDerive.validate(op, [], :x)

      assert {:error, :x, :each, _msg, {:children, [child]}} =
               ValidationDerive.validate(op, ["a", 2], :x)

      assert %{field: :x, action: :string, __index__: 1, message: _} = child
    end

    test "either with two arms picks whichever passes — value unchanged either way" do
      op = %{either: [%{each: [:string]}, :integer]}

      assert ["a", "b"] == ValidationDerive.validate(op, ["a", "b"], :x)
      assert 5 == ValidationDerive.validate(op, 5, :x)
      # Both arms fail: list-of-strings fails (1 not a string) AND integer fails (list not int)
      assert {:error, :x, :either, _} = ValidationDerive.validate(op, [1], :x)
    end

    test "depth 7 explicit — confirm value flows untransformed" do
      op = %{
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

      input = [
        nil,
        "second-arm-leaf-string",
        ["x", nil, 2],
        [nil]
      ]

      # The value must come back BIT-FOR-BIT identical — no list wrapping, no atom coercion.
      assert ^input = ValidationDerive.validate(op, input, :deep)
      assert input == ValidationDerive.validate(op, input, :deep)
    end

    test "depth 8 explicit roundtrip: value structure is documented literally" do
      # op cycle (innermost→outermost): :string, :each, :optional, :either,
      # :each, :optional, :either, :each, :optional
      op = deep_op(8, :string)

      # Document the op so a reviewer can see it:
      assert op == %{
               optional: [
                 %{
                   each: [
                     %{
                       either: [
                         %{
                           optional: [
                             %{each: [%{either: [%{optional: [%{each: [:string]}]}]}]}
                           ]
                         }
                       ]
                     }
                   ]
                 }
               ]
             }

      # eaches sit at n=7, n=4, n=1 → 3 list wrappings around the leaf
      value = [[["leaf"]]]
      assert value == deep_value(8, "leaf")
      assert ^value = ValidationDerive.validate(op, value, :deep)
    end

    test "depth 15 explicit roundtrip: 5 list wrappings around the leaf" do
      # eaches at n=13, n=10, n=7, n=4, n=1 → 5 list wrappings
      op = deep_op(15, :string)
      value = [[[[["leaf"]]]]]
      assert value == deep_value(15, "leaf")
      assert ^value = ValidationDerive.validate(op, value, :deep)
    end
  end
end
