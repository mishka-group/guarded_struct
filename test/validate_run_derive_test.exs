defmodule GuardedStructTest.ValidateRunDeriveTest do
  # Sets the application config the derive lookups read, so it runs apart from
  # the async suites.
  use ExUnit.Case, async: false

  alias GuardedStruct.Derive.Extension
  alias GuardedStruct.Validate
  alias GuardedStructTest.Fixtures.DeriveExtension.SlugDerives

  defmodule Positive do
    def validate(:positive, input, field) do
      if is_integer(input) and input > 0,
        do: input,
        else: {:error, field, :positive, "must be positive"}
    end
  end

  @config_keys [:derive_extensions, :validate_derive, :sanitize_derive]

  setup do
    snapshot = Enum.map(@config_keys, &{&1, Application.fetch_env(:guarded_struct, &1)})
    Enum.each(@config_keys, &Application.delete_env(:guarded_struct, &1))
    Extension.clear_cache()

    on_exit(fn ->
      for {key, saved} <- snapshot do
        case saved do
          {:ok, value} -> Application.put_env(:guarded_struct, key, value)
          :error -> Application.delete_env(:guarded_struct, key)
        end
      end

      Extension.clear_cache()
    end)

    :ok
  end

  @bad_strings [
    {"validate(max_len=foo)", "x"},
    {"validate(min_len=-2)", 5},
    {"validate(tell=abc)", "1"},
    {"validate(record=42)", {:a}},
    {"validate(custom=5)", 1},
    {"validate(each=5)", [1]},
    {"validate(optional=5)", 1},
    {"validate(equal=Integer::abc)", 5},
    {"validate(equal=Float::x)", 1},
    {"validate(equal=Map::%{a: )", 1},
    {"validate(enum=Integer[1::x])", 1},
    {"validate(enum=Atom[a, b])", :a},
    {"validate(enum=Map[%{a: )", 1},
    {"validate(equal=)", 1},
    {"sanitize(clamp=[5, 0])", 1},
    {"sanitize(tag=5)", "x"},
    {"validate(each=[unknown_op])", [1]},
    {"sanitize(each=[unknown_op])", [1]},
    {")))", 1}
  ]

  describe "run/2 with a derive string that is wrong" do
    for {derive, value} <- @bad_strings do
      test "#{derive} returns an error, never {:ok, value} and never a raise" do
        assert {:error, [%{field: :__value__, action: :bad_parameters, message: message}]} =
                 Validate.run(unquote(derive), unquote(Macro.escape(value)))

        assert is_binary(message)
      end
    end

    test "the message names the op and what it expected" do
      assert {:error, [%{message: message}]} = Validate.run("validate(max_len=foo)", "x")
      assert message =~ "max_len"
      assert message =~ "non-negative integer"
    end

    test "a string the parser refuses is quoted in the message" do
      assert {:error, [%{message: message}]} = Validate.run("validate(enum=Atom[a, b])", :a)
      assert message =~ ~S|could not parse the derive string "validate(enum=Atom[a, b])"|
    end

    test "an unknown inner op is named" do
      assert {:error, [%{message: message}]} = Validate.run("validate(each=[unknown_op])", [1])
      assert message =~ ":unknown_op"
    end
  end

  describe "run/2 with a derive string that is right" do
    test "an empty string and an empty group check nothing" do
      assert {:ok, "x"} = Validate.run("", "x")
      assert {:ok, "x"} = Validate.run("validate()", "x")
      assert {:ok, "x"} = Validate.run("sanitize()", "x")
    end

    test "negative numbers, floats and typed equal values are read" do
      assert {:ok, -5} = Validate.run("sanitize(clamp=[-5, 5])", -9)
      assert {:ok, 3} = Validate.run("validate(equal=Integer::3)", 3)
      assert {:ok, 3} = Validate.run(~S|validate(equal="Integer::3")|, 3)
      assert {:error, [%{action: :equal}]} = Validate.run("validate(equal=Integer::3)", 4)
    end

    test "combinators with built-in ops" do
      assert {:ok, ["a"]} = Validate.run("validate(each=[string, not_empty])", ["a"])
    end

    test "a top-level op nothing defines is a type error at run time, as in a module" do
      assert {:error, [%{action: :type}]} = Validate.run("validate(not_empty, no_such_op)", "x")
    end
  end

  describe "run/2 inner ops from the configuration" do
    test "an op of a derive extension is known inside each" do
      Application.put_env(:guarded_struct, :derive_extensions, [SlugDerives])
      Extension.clear_cache()

      assert {:ok, ["a-b"]} = Validate.run("validate(each=[my_slug])", ["a-b"])
      assert {:error, [%{action: :my_slug}]} = Validate.run("validate(each=[my_slug])", ["A B"])

      assert {:error, [%{action: :bad_parameters}]} =
               Validate.run("validate(each=[other])", ["a"])
    end

    test "a validate_derive module makes any inner op name acceptable" do
      Application.put_env(:guarded_struct, :validate_derive, Positive)

      assert {:ok, [1, 2]} = Validate.run("validate(each=[positive])", [1, 2])

      assert {:error, [%{action: :positive, __index__: 1}]} =
               Validate.run("validate(each=[positive])", [1, -2])
    end
  end
end
