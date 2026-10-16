defmodule GuardedStructTest.ParserStringFormTest do
  @moduledoc """
  Unit tests for `GuardedStruct.Derive.Parser` covering the string-form
  derive grammar: regex patterns, parameterised ops (`min_len=`,
  `regex=`, `clamp=`), list-shaped ops (`each=`, `optional=`), and the
  bare named aliases (`slug`, `hostname`, …).
  """

  use ExUnit.Case, async: true

  alias GuardedStruct.Derive.Parser

  describe "parser/1 with regex= op" do
    test "simple pattern parses to pre-compiled %Regex{}" do
      assert %{validate: [{:regex, %Regex{source: "^[a-z]+$"}}]} =
               Parser.parser("validate(regex=^[a-z]+$)")
    end

    test "pattern with hyphen-range and dot inside character class" do
      assert %{validate: [{:regex, %Regex{source: "^[a-z0-9.-]+$"}}]} =
               Parser.parser("validate(regex=^[a-z0-9.-]+$)")
    end

    test "pattern with uppercase, digits, dot, and hyphen" do
      assert %{validate: [{:regex, %Regex{source: "^[a-zA-Z0-9.-]+$"}}]} =
               Parser.parser("validate(regex=^[a-zA-Z0-9.-]+$)")
    end

    test "regex op mixed with sanitize and other validate ops keeps every op" do
      derive_str =
        "sanitize(trim, downcase) validate(string, not_empty, min_len=3, max_len=200, regex=^[a-z0-9.-]+$)"

      assert %{
               sanitize: [:trim, :downcase],
               validate: [
                 :string,
                 :not_empty,
                 {:min_len, 3},
                 {:max_len, 200},
                 {:regex, %Regex{source: "^[a-z0-9.-]+$"}}
               ]
             } = Parser.parser(derive_str)
    end

    test "literal-quoted regex pattern still works" do
      assert %{validate: [{:regex, %Regex{source: "^foo$"}}]} =
               Parser.parser(~S{validate(regex="^foo$")})
    end

    test "escaped-dot pattern from the global_test.exs fixture parses" do
      input = "validate(regex=#{~c"^[a-zA-Z]+@mishka\\.group$"})"

      assert %{validate: [{:regex, %Regex{} = regex}]} = Parser.parser(input)
      assert Regex.source(regex) =~ "mishka"
    end

    test "unquoted regex nested inside each=[...] balances brackets correctly" do
      assert %{
               validate: [
                 %{
                   each: [
                     {:regex, %Regex{source: "^https?://[-a-z0-9./:]+$"}}
                   ]
                 }
               ]
             } = Parser.parser("validate(each=[regex=^https?://[-a-z0-9./:]+$])")
    end

    test "regex nested in each= alongside other ops keeps every op" do
      input =
        "sanitize(each=[trim, downcase]) validate(list, max_len=20, each=[regex=^https?://[-a-z0-9./:]+$])"

      assert %{
               sanitize: [%{each: [:trim, :downcase]}],
               validate: [
                 :list,
                 {:max_len, 20},
                 %{each: [{:regex, %Regex{source: "^https?://[-a-z0-9./:]+$"}}]}
               ]
             } = Parser.parser(input)
    end
  end

  describe "ValidationDerive end-to-end after parser fix" do
    test "parsed regex op rejects non-matching input at validate-time" do
      %{validate: ops} = Parser.parser("validate(regex=^[a-z]+$)")

      {_first, errors} =
        GuardedStruct.Derive.ValidationDerive.call({:slug, "bad_value"}, ops, [])

      assert [%{field: :slug, action: :regex, message: msg}] = errors
      assert msg =~ "Invalid format in the slug field"
    end

    test "parsed regex op accepts matching input" do
      %{validate: ops} = Parser.parser("validate(regex=^[a-z]+$)")

      {first, errors} =
        GuardedStruct.Derive.ValidationDerive.call({:slug, "lowercase"}, ops, [])

      assert first == "lowercase"
      assert errors == []
    end
  end

  describe "list/string hygiene sanitizers parse as bare atoms" do
    test "list hygiene set" do
      assert %{sanitize: [:uniq, :compact, :reject_empty, :sort]} =
               Parser.parser("sanitize(uniq, compact, reject_empty, sort)")
    end

    test "string hygiene set" do
      assert %{sanitize: [:squish, :no_control, :no_zero_width]} =
               Parser.parser("sanitize(squish, no_control, no_zero_width)")
    end

    test ":rich_text_safe parses as a bare atom" do
      assert %{sanitize: [:rich_text_safe]} = Parser.parser("sanitize(rich_text_safe)")
    end

    test ":rich_text_safe composes with other sanitize ops in one block" do
      assert %{sanitize: [:trim, :rich_text_safe, :squish]} =
               Parser.parser("sanitize(trim, rich_text_safe, squish)")
    end
  end

  describe "parameterised sanitizer ops" do
    test "clamp=[0, 100] parses to tuple form" do
      assert %{sanitize: [{:clamp, [0, 100]}]} =
               Parser.parser("sanitize(clamp=[0, 100])")
    end

    test "default_when_nil=0 parses to tuple form" do
      assert %{sanitize: [{:default_when_nil, 0}]} =
               Parser.parser("sanitize(default_when_nil=0)")
    end

    test "default_when_empty=nil parses to {key, nil} (was silently dropped before)" do
      assert %{sanitize: [{:default_when_empty, nil}]} =
               Parser.parser("sanitize(default_when_empty=nil)")
    end

    test "default_when_nil=nil parses (no-op semantically, but no longer silently dropped)" do
      assert %{sanitize: [{:default_when_nil, nil}]} =
               Parser.parser("sanitize(default_when_nil=nil)")
    end
  end

  describe "named regex aliases parse as bare atoms" do
    test "slug, hostname, port_number, hex_color, semver" do
      assert %{validate: [:slug]} = Parser.parser("validate(slug)")
      assert %{validate: [:hostname]} = Parser.parser("validate(hostname)")
      assert %{validate: [:port_number]} = Parser.parser("validate(port_number)")
      assert %{validate: [:hex_color]} = Parser.parser("validate(hex_color)")
      assert %{validate: [:semver]} = Parser.parser("validate(semver)")
    end
  end

  describe "each combinator" do
    test "sanitize each=[trim, downcase] parses to map form" do
      assert %{sanitize: [%{each: [:trim, :downcase]}]} =
               Parser.parser("sanitize(each=[trim, downcase])")
    end

    test "validate each=[string, max_len=200] parses to map form" do
      assert %{validate: [%{each: [:string, {:max_len, 200}]}]} =
               Parser.parser("validate(each=[string, max_len=200])")
    end
  end

  describe "optional wrapper" do
    test "optional=[string, max_len=3] parses to map form" do
      assert %{validate: [%{optional: [:string, {:max_len, 3}]}]} =
               Parser.parser("validate(optional=[string, max_len=3])")
    end
  end

  # The bare-atom form (no brackets) is the one that used to materialise
  # a binary inner op and force a String.to_existing_atom rescue at validate
  # time. The parser now wraps it in a 1-element atom list so the runtime
  # never has to atomize.
  describe "optional / each — bare-atom value normalization" do
    test "optional=string produces {:optional, [:string]} (atom, not binary)" do
      assert %{validate: [{:optional, [:string]}]} =
               Parser.parser("validate(optional=string)")
    end

    test "each=trim produces {:each, [:trim]} on sanitize side" do
      assert %{sanitize: [{:each, [:trim]}]} =
               Parser.parser("sanitize(each=trim)")
    end

    test "each=string produces {:each, [:string]} on validate side" do
      assert %{validate: [{:each, [:string]}]} =
               Parser.parser("validate(each=string)")
    end

    test "bracketed form produces map shape (all atoms)" do
      assert %{validate: [%{each: [:string, :not_empty]}]} =
               Parser.parser("validate(each=[string, not_empty])")
    end

    test "bracketed form with parameterised inner also produces map shape" do
      assert %{validate: [%{each: [:string, {:max_len, 20}]}]} =
               Parser.parser("validate(each=[string, max_len=20])")
    end
  end

  # `equal=Type::value` reads as `(equal=Type)::value` to the Elixir parser, so
  # the value is lifted into a string literal before the AST is built.
  describe "equal=Type::value operands" do
    test "Integer::value" do
      assert %{validate: [{:equal, "Integer::1"}]} = Parser.parser("validate(equal=Integer::1)")
    end

    test "negative Integer::value" do
      assert %{validate: [{:equal, "Integer::-1"}]} =
               Parser.parser("validate(equal=Integer::-1)")
    end

    test "Float::value" do
      assert %{validate: [{:equal, "Float::1.5"}]} = Parser.parser("validate(equal=Float::1.5)")
    end

    test "String::value keeps spaces inside the value" do
      assert %{validate: [{:equal, "String::hello world"}]} =
               Parser.parser("validate(equal=String::hello world)")
    end

    test "Atom::value" do
      assert %{validate: [{:equal, "Atom::admin"}]} = Parser.parser("validate(equal=Atom::admin)")
    end

    test "Map::value keeps the commas inside the braces" do
      assert %{validate: [{:equal, "Map::%{a: 1, b: 2}"}]} =
               Parser.parser("validate(equal=Map::%{a: 1, b: 2})")
    end

    test "Tuple::value keeps the commas inside the braces" do
      assert %{validate: [{:equal, "Tuple::{:a, 1}"}]} =
               Parser.parser("validate(equal=Tuple::{:a, 1})")
    end

    test "the ops written after it are kept" do
      assert %{validate: [:string, {:equal, "String::admin"}, {:max_len, 10}]} =
               Parser.parser("validate(string, equal=String::admin, max_len=10)")
    end

    test "inside either=[...]" do
      assert %{validate: [%{either: [{:equal, "Integer::1"}, :string]}]} =
               Parser.parser("validate(either=[equal=Integer::1, string])")
    end

    test "inside each=[...]" do
      assert %{validate: [%{each: [{:equal, "String::a"}, {:max_len, 3}]}]} =
               Parser.parser("validate(each=[equal=String::a, max_len=3])")
    end

    test "whitespace around the equals sign is kept out of the value" do
      assert %{validate: [{:equal, "Integer::1"}]} = Parser.parser("validate(equal = Integer::1)")
    end

    test "an untyped value keeps parsing as before" do
      assert %{validate: [{:equal, "admin"}]} = Parser.parser("validate(equal=admin)")
      assert %{validate: [{:equal, 3}]} = Parser.parser("validate(equal=3)")
    end

    test "another op that ends in `equal` is not rewritten" do
      assert %{validate: [{:invalid_operand, _source}]} =
               Parser.parser("validate(not_equal=Integer::1)")
    end
  end

  describe "negative number operands" do
    test "min_len=-2 parses to a negative integer" do
      assert %{validate: [{:min_len, -2}]} = Parser.parser("validate(min_len=-2)")
    end

    test "clamp=[-10, 10]" do
      assert %{sanitize: [{:clamp, [-10, 10]}]} = Parser.parser("sanitize(clamp=[-10, 10])")
    end

    test "clamp=[-2.5, -0.5]" do
      assert %{sanitize: [{:clamp, [-2.5, -0.5]}]} = Parser.parser("sanitize(clamp=[-2.5, -0.5])")
    end

    test "default_when_empty=-1" do
      assert %{sanitize: [{:default_when_empty, -1}]} =
               Parser.parser("sanitize(default_when_empty=-1)")
    end

    test "default_when_nil=-1.5" do
      assert %{sanitize: [{:default_when_nil, -1.5}]} =
               Parser.parser("sanitize(default_when_nil=-1.5)")
    end

    test "inside each=[...]" do
      assert %{validate: [%{each: [{:min_len, -1}]}]} =
               Parser.parser("validate(each=[min_len=-1])")
    end

    test "equal=-3" do
      assert %{validate: [{:equal, -3}]} = Parser.parser("validate(equal=-3)")
    end
  end

  describe "float and literal operands" do
    test "default_when_empty=1.5" do
      assert %{sanitize: [{:default_when_empty, 1.5}]} =
               Parser.parser("sanitize(default_when_empty=1.5)")
    end

    test "max_len=1.5 is kept for OpParamValidator to reject" do
      assert %{validate: [{:max_len, 1.5}]} = Parser.parser("validate(max_len=1.5)")
    end

    test "default_when_nil=true and false" do
      assert %{sanitize: [{:default_when_nil, true}]} =
               Parser.parser("sanitize(default_when_nil=true)")

      assert %{sanitize: [{:default_when_nil, false}]} =
               Parser.parser("sanitize(default_when_nil=false)")
    end

    test "default_when_nil=:none keeps the atom" do
      assert %{sanitize: [{:default_when_nil, :none}]} =
               Parser.parser("sanitize(default_when_nil=:none)")
    end

    test "default_when_empty=%{} and a tuple literal" do
      assert %{sanitize: [{:default_when_empty, %{}}]} =
               Parser.parser("sanitize(default_when_empty=%{})")

      assert %{sanitize: [{:default_when_empty, {:ok, 1}}]} =
               Parser.parser("sanitize(default_when_empty={:ok, 1})")
    end
  end

  describe "operands that cannot be parsed" do
    test "a call is kept as {:invalid_operand, source}" do
      assert %{validate: [{:invalid_operand, "max_len = foo()"}]} =
               Parser.parser("validate(max_len=foo())")
    end

    test "a bare number is kept as {:invalid_operand, source}" do
      assert %{validate: [:string, {:invalid_operand, "5"}]} =
               Parser.parser("validate(string, 5)")
    end

    test "inside a list of ops" do
      assert %{validate: [%{either: [:string, {:invalid_operand, _source}]}]} =
               Parser.parser("validate(either=[string, max_len=foo()])")
    end

    test "custom= with an unexpected shape" do
      assert %{validate: [{:invalid_operand, _source}]} = Parser.parser("validate(custom=[1, 2])")
    end

    test "the ops around it are still parsed" do
      assert %{sanitize: [:trim, {:invalid_operand, _source}, :upcase]} =
               Parser.parser("sanitize(trim, default_when_nil=foo(), upcase)")
    end
  end

  describe "parse/1" do
    test "nil and empty input have no ops" do
      assert {:ok, nil} = Parser.parse(nil)
      assert {:ok, nil} = Parser.parse("")
    end

    test "returns the ops of a valid string" do
      assert {:ok, %{sanitize: [:trim], validate: [:string, {:max_len, 3}]}} =
               Parser.parse("sanitize(trim) validate(string, max_len=3)")
    end

    test "a string the Elixir parser refuses is an error with the reason" do
      assert {:error, reason} = Parser.parse("validate(string,,)")
      assert is_binary(reason)
      assert reason != ""
    end

    test "enum=Atom[a, b] (comma instead of ::) is an error" do
      assert {:error, reason} = Parser.parse("validate(enum=Atom[admin, user])")
      refute reason =~ "\n"
    end

    test "parser/1 turns the same error into nil" do
      assert Parser.parser("validate(string,,)") == nil
    end
  end
end
