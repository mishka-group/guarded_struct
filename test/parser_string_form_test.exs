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
end
