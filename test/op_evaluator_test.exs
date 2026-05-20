defmodule GuardedStructTest.OpEvaluatorTest do
  use ExUnit.Case, async: true

  alias GuardedStruct.Derive.OpEvaluator

  describe "preevaluate/1 — nil + empty" do
    test "nil passes through" do
      assert nil == OpEvaluator.preevaluate(nil)
    end

    test "empty map passes through unchanged" do
      assert %{} == OpEvaluator.preevaluate(%{})
    end

    test "ops without rewrite-eligible entries pass through" do
      ops = %{validate: [:string, :not_empty], sanitize: [:trim]}
      assert ^ops = OpEvaluator.preevaluate(ops)
    end
  end

  describe "preevaluate/1 — :enum rewrites" do
    test "String[a::b::c] resolves to string list" do
      assert %{validate: [{:enum, ["a", "b", "c"]}]} =
               OpEvaluator.preevaluate(%{validate: [{:enum, "String[a::b::c]"}]})
    end

    test "Atom[red::green::blue] resolves to atom list" do
      assert %{validate: [{:enum, [:red, :green, :blue]}]} =
               OpEvaluator.preevaluate(%{validate: [{:enum, "Atom[red::green::blue]"}]})
    end

    test "Integer[1::2::3] resolves to integer list" do
      assert %{validate: [{:enum, [1, 2, 3]}]} =
               OpEvaluator.preevaluate(%{validate: [{:enum, "Integer[1::2::3]"}]})
    end

    test "Float[1.5::2.5] resolves to float list" do
      assert %{validate: [{:enum, [1.5, 2.5]}]} =
               OpEvaluator.preevaluate(%{validate: [{:enum, "Float[1.5::2.5]"}]})
    end
  end

  describe "preevaluate/1 — :equal rewrites" do
    test "String::hello strips prefix" do
      assert %{validate: [{:equal, "hello"}]} =
               OpEvaluator.preevaluate(%{validate: [{:equal, "String::hello"}]})
    end

    test "Integer::42 parses to integer" do
      assert %{validate: [{:equal, 42}]} =
               OpEvaluator.preevaluate(%{validate: [{:equal, "Integer::42"}]})
    end

    test "Integer::bad leaves original string when parse fails" do
      assert %{validate: [{:equal, "Integer::bad"}]} =
               OpEvaluator.preevaluate(%{validate: [{:equal, "Integer::bad"}]})
    end

    test "Float::3.14 parses to float" do
      assert %{validate: [{:equal, 3.14}]} =
               OpEvaluator.preevaluate(%{validate: [{:equal, "Float::3.14"}]})
    end

    test "Atom::user atomizes the value" do
      assert %{validate: [{:equal, :user}]} =
               OpEvaluator.preevaluate(%{validate: [{:equal, "Atom::user"}]})
    end
  end

  describe "preevaluate/1 — :record rewrite (#3 compile-time atomization)" do
    test "binary tag is atomized" do
      assert %{validate: [{:record, :user}]} =
               OpEvaluator.preevaluate(%{validate: [{:record, "user"}]})
    end

    test "atom tag stays untouched" do
      assert %{validate: [{:record, :user}]} =
               OpEvaluator.preevaluate(%{validate: [{:record, :user}]})
    end

    test "bare :record (no tag) stays untouched" do
      assert %{validate: [:record]} =
               OpEvaluator.preevaluate(%{validate: [:record]})
    end
  end

  describe "preevaluate/1 — :custom rewrite (#4 compile-time module resolution)" do
    test "module-list + atom fun resolves to {Module, fun}" do
      assert %{validate: [{:custom, {Enum, :sum}}]} =
               OpEvaluator.preevaluate(%{validate: [{:custom, {[:Enum], :sum}}]})
    end

    test "nested module-list resolves to dotted module" do
      assert %{validate: [{:custom, {String.Chars, :to_string}}]} =
               OpEvaluator.preevaluate(%{
                 validate: [{:custom, {[:String, :Chars], :to_string}}]
               })
    end

    test "string form 'Mod,fn' resolves to {Module, atom_fn}" do
      assert %{validate: [{:custom, {Enum, :sum}}]} =
               OpEvaluator.preevaluate(%{validate: [{:custom, "Enum,sum"}]})
    end

    test "string form with brackets and spaces still resolves" do
      assert %{validate: [{:custom, {Enum, :sum}}]} =
               OpEvaluator.preevaluate(%{validate: [{:custom, "[Enum, sum]"}]})
    end

    test "string form without exactly 2 parts leaves original value" do
      assert %{validate: [{:custom, "Enum"}]} =
               OpEvaluator.preevaluate(%{validate: [{:custom, "Enum"}]})
    end
  end

  describe "rewrite_tuple/1 — direct one-tuple rewrites (domain helper path)" do
    test "rewrites :record binary tag" do
      assert {:record, :user} = OpEvaluator.rewrite_tuple({:record, "user"})
    end

    test "rewrites :custom string form" do
      assert {:custom, {Enum, :sum}} = OpEvaluator.rewrite_tuple({:custom, "Enum,sum"})
    end

    test "passes through unrecognised tuples unchanged" do
      assert {:max_len, 20} = OpEvaluator.rewrite_tuple({:max_len, 20})
    end
  end
end
