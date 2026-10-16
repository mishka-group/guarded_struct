defmodule GuardedStructTest.DeriveOperandsTest do
  @moduledoc """
  Derive-string operands through `builder/1`: `equal=Type::value`, negative
  and float numbers, an empty op group, and the compile-time `DslError` for an
  operand or a whole derive string that cannot be parsed.
  """

  use ExUnit.Case, async: true

  defmodule TypedEqual do
    use GuardedStruct

    guardedstruct do
      field(:count, integer(), derives: "validate(equal=Integer::1)")
      field(:ratio, float(), derives: "validate(equal=Float::1.5)")
      field(:role, String.t(), derives: "validate(equal=String::site admin)")
      field(:kind, atom(), derives: "validate(equal=Atom::admin)")
      field(:meta, map(), derives: "validate(equal=Map::%{a: 1, b: 2})")
      field(:pair, tuple(), derives: "validate(equal=Tuple::{:a, 1})")
      field(:delta, integer(), derives: "validate(equal=Integer::-1)")
    end
  end

  defmodule TypedEqualAmongOps do
    use GuardedStruct

    guardedstruct do
      field(:role, String.t(), derives: "sanitize(trim) validate(string, equal=String::admin)")
      field(:level, any(), derives: "validate(either=[equal=Integer::1, equal=String::one])")
    end
  end

  defmodule NumberOperands do
    use GuardedStruct

    guardedstruct do
      field(:temp, integer(), derives: "sanitize(clamp=[-10, 10])")
      field(:score, number(), derives: "sanitize(default_when_empty=-1)")
      field(:ratio, float(), derives: "sanitize(default_when_empty=1.5)")
      field(:tags, list(), derives: "sanitize(default_when_empty=[])")
    end
  end

  defmodule EmptyGroups do
    use GuardedStruct

    guardedstruct do
      field(:x, integer(), derives: "validate()")
      field(:y, String.t(), derives: "sanitize()")
      field(:z, String.t(), derives: "sanitize() validate()")
    end
  end

  defp compile(derive) do
    src = """
    defmodule DeriveOperands#{:erlang.unique_integer([:positive])} do
      use GuardedStruct

      guardedstruct do
        field(:value, term(), derives: #{inspect(derive)})
      end
    end
    """

    Code.compile_string(src)
  end

  describe "equal=Type::value through builder/1" do
    test "a matching value is kept, whatever the type" do
      assert {:ok,
              %TypedEqual{
                count: 1,
                ratio: 1.5,
                role: "site admin",
                kind: :admin,
                meta: %{a: 1, b: 2},
                pair: {:a, 1},
                delta: -1
              }} =
               TypedEqual.builder(%{
                 count: 1,
                 ratio: 1.5,
                 role: "site admin",
                 kind: :admin,
                 meta: %{a: 1, b: 2},
                 pair: {:a, 1},
                 delta: -1
               })
    end

    test "a different value is refused with an :equal error on that field" do
      for {field, wrong} <- [
            count: 2,
            ratio: 2.5,
            role: "editor",
            kind: :guest,
            meta: %{a: 2},
            pair: {:a, 2},
            delta: 1
          ] do
        assert {:error, errors} = TypedEqual.builder(%{field => wrong})

        assert Enum.any?(errors, &(&1.field == field and &1.action == :equal)),
               "#{field}: #{inspect(wrong)} was not refused: #{inspect(errors)}"
      end
    end

    test "the field does not come back as nil" do
      assert {:ok, %TypedEqual{count: 1}} = TypedEqual.builder(%{count: 1})
    end

    test "next to other ops in the same group" do
      assert {:ok, %TypedEqualAmongOps{role: "admin"}} =
               TypedEqualAmongOps.builder(%{role: "  admin  "})

      assert {:error, errors} = TypedEqualAmongOps.builder(%{role: "  editor  "})
      assert Enum.any?(errors, &(&1.field == :role and &1.action == :equal))
    end

    test "inside either=[...]" do
      assert {:ok, %TypedEqualAmongOps{level: 1}} = TypedEqualAmongOps.builder(%{level: 1})

      assert {:ok, %TypedEqualAmongOps{level: "one"}} =
               TypedEqualAmongOps.builder(%{level: "one"})

      assert {:error, errors} = TypedEqualAmongOps.builder(%{level: 2})
      assert Enum.any?(errors, &(&1.field == :level and &1.action == :either))
    end
  end

  describe "negative and float operands through builder/1" do
    test "clamp=[-10, 10] holds a number to its negative bound" do
      assert {:ok, %NumberOperands{temp: -10}} = NumberOperands.builder(%{temp: -50})
      assert {:ok, %NumberOperands{temp: 10}} = NumberOperands.builder(%{temp: 50})
      assert {:ok, %NumberOperands{temp: -3}} = NumberOperands.builder(%{temp: -3})
    end

    test "default_when_empty=-1 fills an empty string" do
      assert {:ok, %NumberOperands{score: -1}} = NumberOperands.builder(%{score: ""})
      assert {:ok, %NumberOperands{score: 7}} = NumberOperands.builder(%{score: 7})
    end

    test "default_when_empty=1.5 fills an empty string" do
      assert {:ok, %NumberOperands{ratio: 1.5}} = NumberOperands.builder(%{ratio: ""})
    end

    test "default_when_empty=[] fills an empty string" do
      assert {:ok, %NumberOperands{tags: []}} = NumberOperands.builder(%{tags: ""})
    end
  end

  describe "an op group with nothing to run" do
    test "validate() keeps the value" do
      assert {:ok, %EmptyGroups{x: 5}} = EmptyGroups.builder(%{x: 5})
    end

    test "sanitize() keeps the value" do
      assert {:ok, %EmptyGroups{y: "ab"}} = EmptyGroups.builder(%{y: "ab"})
    end

    test "both empty keep the value" do
      assert {:ok, %EmptyGroups{z: "ab"}} = EmptyGroups.builder(%{z: "ab"})
    end

    test "ValidationDerive.call/3 with no actions returns the input and no errors" do
      assert {5, []} = GuardedStruct.Derive.ValidationDerive.call({:x, 5}, [], [])
    end
  end

  describe "compile-time DslError for an operand that cannot be used" do
    test "min_len=-2" do
      assert_raise Spark.Error.DslError, ~r/`min_len`.*non-negative integer.*got -2/, fn ->
        compile("validate(min_len=-2)")
      end
    end

    test "max_len=1.5" do
      assert_raise Spark.Error.DslError, ~r/`max_len`.*non-negative integer.*got 1.5/, fn ->
        compile("validate(max_len=1.5)")
      end
    end

    test "max_len=foo" do
      assert_raise Spark.Error.DslError, ~r/`max_len`.*got "foo"/, fn ->
        compile("validate(max_len=foo)")
      end
    end

    test "clamp=[10, -10]" do
      assert_raise Spark.Error.DslError, ~r/`clamp`/, fn ->
        compile("sanitize(clamp=[10, -10])")
      end
    end

    test "a negative bound inside each=[...]" do
      assert_raise Spark.Error.DslError, ~r/`min_len`/, fn ->
        compile("validate(each=[min_len=-1])")
      end
    end

    test "an operand the parser does not understand" do
      assert_raise Spark.Error.DslError,
                   ~r/could not parse the operand `max_len = foo\(\)`/,
                   fn ->
                     compile("validate(max_len=foo())")
                   end
    end

    test "an operand inside either=[...] and each=[...]" do
      assert_raise Spark.Error.DslError, ~r/could not parse the operand/, fn ->
        compile("validate(either=[string, max_len=foo()])")
      end

      assert_raise Spark.Error.DslError, ~r/could not parse the operand/, fn ->
        compile("sanitize(each=[trim, default_when_nil=foo()])")
      end
    end

    test "equal=Integer:: with a value that is not an integer" do
      assert_raise Spark.Error.DslError, ~r/`equal`.*Integer::abc/, fn ->
        compile("validate(equal=Integer::abc)")
      end
    end

    test "equal=Map:: with code that does not evaluate" do
      assert_raise Spark.Error.DslError, ~r/`equal`/, fn ->
        compile("validate(equal=Map::%{a:)")
      end
    end

    test "enum=Integer[...] with values that are not integers" do
      assert_raise Spark.Error.DslError, ~r/`enum`/, fn ->
        compile("validate(enum=Integer[a::b])")
      end
    end

    test "a derives string the Elixir parser refuses" do
      assert_raise Spark.Error.DslError, ~r/could not parse the derives string/, fn ->
        compile("validate(string,,)")
      end
    end

    test "enum=Atom[a, b], which separates its values with a comma instead of ::" do
      assert_raise Spark.Error.DslError, ~r/enum=Type\[a::b\]/, fn ->
        compile("validate(enum=Atom[admin, user])")
      end
    end

    test "the error names the field, the module and the derives string" do
      error =
        assert_raise Spark.Error.DslError, fn -> compile("validate(string,,)") end

      assert error.path == [:guardedstruct, :field, :value, :derives]
      assert error.message =~ ":value"
      assert error.message =~ "validate(string,,)"
      assert inspect(error.module) =~ "DeriveOperands"
    end
  end

  describe "operands that do compile" do
    test "every typed, negative and float form" do
      for derive <- [
            "validate(equal=Integer::-5)",
            "validate(equal=Float::-0.5)",
            "validate(equal=-3)",
            "validate(min_len=0)",
            "sanitize(clamp=[-1.5, 1.5])",
            "sanitize(default_when_nil=-1)",
            "sanitize(default_when_nil=false)",
            "validate(enum=Integer[-1::0::1])",
            "validate(enum=Float[-1.5::2.5])"
          ] do
        assert [{module, _binary}] = compile(derive)
        assert Code.ensure_loaded?(module)
      end
    end
  end

  describe "the same operands through Validate.run/2" do
    alias GuardedStruct.Validate

    test "equal=String::value" do
      assert {:ok, "admin"} = Validate.run("validate(equal=String::admin)", "admin")

      assert {:error, [%{action: :equal}]} =
               Validate.run("validate(equal=String::admin)", "editor")
    end

    test "equal=Integer::value, negative or not" do
      assert {:ok, 1} = Validate.run("validate(equal=Integer::1)", 1)
      assert {:error, [%{action: :equal}]} = Validate.run("validate(equal=Integer::1)", 2)
      assert {:ok, -1} = Validate.run("validate(equal=Integer::-1)", -1)
    end

    test "equal=Map::value" do
      assert {:ok, %{a: 1}} = Validate.run("validate(equal=Map::%{a: 1})", %{a: 1})
      assert {:error, [%{action: :equal}]} = Validate.run("validate(equal=Map::%{a: 1})", %{a: 2})
    end

    test "clamp and default_when_empty with negative and float operands" do
      assert {:ok, -10} = Validate.run("sanitize(clamp=[-10, 10])", -50)
      assert {:ok, -1} = Validate.run("sanitize(default_when_empty=-1)", "")
      assert {:ok, 1.5} = Validate.run("sanitize(default_when_empty=1.5)", "")
    end

    test "an operand that cannot be parsed fails the value instead of being skipped" do
      assert {:error, [%{action: :type}]} = Validate.run("validate(max_len=foo())", "abc")
    end
  end
end
