defmodule GuardedStructTest.RegexThroughPipelineTest do
  @moduledoc """
  End-to-end regex coverage across the three layers GuardedStruct exposes:

    1. `Parser.parser/1` — does the string-form derive parse to
       `%Regex{}` ops correctly, especially when the pattern itself contains
       characters that overlap with the derive grammar (`,`, `)`, `[`, `]`,
       `\\`, lookarounds, alternation)?
    2. `ValidationDerive.validate/3` — does the pre-compiled `%Regex{}`
       accept matching input and reject non-matching input?
    3. `Module.builder/1` (the full macro pipeline) — does a real
       `use GuardedStruct` module wired with `derives: "validate(regex=…)"`
       produce the right struct or canonical error list?

  Every test pins full expected output so the file doubles as documentation
  of "this regex shape parses to this AST and accepts/rejects these inputs."
  """

  use ExUnit.Case, async: true

  alias GuardedStruct.Derive.{Parser, ValidationDerive}

  defmodule WordsOnly do
    use GuardedStruct

    guardedstruct do
      field(:value, String.t(), derives: "validate(regex=^[a-z]+$)")
    end
  end

  defmodule DigitsOnly do
    use GuardedStruct

    guardedstruct do
      field(:value, String.t(), derives: "validate(regex=^\\d+$)")
    end
  end

  defmodule EmailLike do
    use GuardedStruct

    guardedstruct do
      field(:value, String.t(),
        derives: "validate(regex=^[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}$)"
      )
    end
  end

  defmodule HexColor do
    use GuardedStruct

    guardedstruct do
      field(:value, String.t(), derives: "validate(regex=^#[0-9a-fA-F]{6}$)")
    end
  end

  defmodule IPv4Like do
    use GuardedStruct

    guardedstruct do
      field(:value, String.t(),
        derives: "validate(regex=^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$)"
      )
    end
  end

  defmodule UrlWithParens do
    use GuardedStruct

    guardedstruct do
      field(:value, String.t(),
        derives: "validate(regex=^https?://[a-z0-9.-]+(:[0-9]+)?(/.*)?$)"
      )
    end
  end

  defmodule NegatedClass do
    use GuardedStruct

    guardedstruct do
      field(:value, String.t(), derives: "validate(regex=^[^,]+$)")
    end
  end

  defmodule LookaheadPassword do
    use GuardedStruct

    guardedstruct do
      field(:value, String.t(),
        derives: "validate(regex=^(?=.*[A-Z])(?=.*\\d)[A-Za-z\\d]{8,}$)"
      )
    end
  end

  defmodule NestedEachRegex do
    use GuardedStruct

    guardedstruct do
      field(:tags, list(),
        derives:
          "sanitize(each=[trim, downcase], uniq) validate(list, max_len=10, each=[regex=^[a-z0-9-]+$])"
      )
    end
  end

  defmodule NestedOptionalRegex do
    use GuardedStruct

    guardedstruct do
      field(:slug, any(),
        derives: "validate(optional=[regex=^[a-z]+(-[a-z]+)*$])"
      )
    end
  end

  defmodule EitherWithRegex do
    use GuardedStruct

    guardedstruct do
      field(:value, any(), derives: "validate(either=[integer, regex=^[A-Z]{2,}$])")
    end
  end

  defmodule LongRealistic do
    use GuardedStruct

    guardedstruct do
      field(:value, String.t(),
        derives:
          "sanitize(trim, downcase) validate(string, not_empty, max_len=120, regex=^https?://[a-z0-9.-]+(:[0-9]+)?(/[a-z0-9._~%/?#@!$&'()*+,;=:-]*)?$)"
      )
    end
  end

  describe "parser layer — every regex parses to {:regex, %Regex{source: …}}" do
    test "[a-z]+ — simple lowercase word" do
      assert %{validate: [{:regex, %Regex{source: "^[a-z]+$"}}]} =
               Parser.parser("validate(regex=^[a-z]+$)")
    end

    test "\\d+ — backslash escape for digits" do
      assert %{validate: [{:regex, %Regex{source: "^\\d+$"}}]} =
               Parser.parser("validate(regex=^\\d+$)")
    end

    test "email — character class with %+-, anchors, escaped dot, quantifier" do
      assert %{
               validate: [
                 {:regex, %Regex{source: "^[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}$"}}
               ]
             } =
               Parser.parser(
                 "validate(regex=^[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}$)"
               )
    end

    test "hex color — fixed-length quantifier {6}" do
      assert %{validate: [{:regex, %Regex{source: "^#[0-9a-fA-F]{6}$"}}]} =
               Parser.parser("validate(regex=^#[0-9a-fA-F]{6}$)")
    end

    test "ipv4 — four bracket-balanced groups via escapes" do
      assert %{
               validate: [
                 {:regex,
                  %Regex{source: "^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$"}}
               ]
             } =
               Parser.parser(
                 "validate(regex=^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$)"
               )
    end

    test "url with parens — the case the old heuristic broke on" do
      assert %{
               validate: [
                 {:regex, %Regex{source: "^https?://[a-z0-9.-]+(:[0-9]+)?(/.*)?$"}}
               ]
             } =
               Parser.parser(
                 "validate(regex=^https?://[a-z0-9.-]+(:[0-9]+)?(/.*)?$)"
               )
    end

    test "negated character class [^,] — comma inside the pattern" do
      assert %{validate: [{:regex, %Regex{source: "^[^,]+$"}}]} =
               Parser.parser("validate(regex=^[^,]+$)")
    end

    test "lookahead — (?=.*[A-Z])(?=.*\\d)" do
      assert %{
               validate: [
                 {:regex, %Regex{source: "^(?=.*[A-Z])(?=.*\\d)[A-Za-z\\d]{8,}$"}}
               ]
             } =
               Parser.parser(
                 "validate(regex=^(?=.*[A-Z])(?=.*\\d)[A-Za-z\\d]{8,}$)"
               )
    end

    test "alternation — (foo|bar|baz)" do
      assert %{validate: [{:regex, %Regex{source: "^(foo|bar|baz)$"}}]} =
               Parser.parser("validate(regex=^(foo|bar|baz)$)")
    end

    test "nested in each=[regex=...] — bracket balancing" do
      assert %{
               validate: [
                 %{each: [{:regex, %Regex{source: "^[a-z0-9-]+$"}}]}
               ]
             } =
               Parser.parser("validate(each=[regex=^[a-z0-9-]+$])")
    end

    test "nested in optional=[regex=...]" do
      assert %{
               validate: [
                 %{optional: [{:regex, %Regex{source: "^[a-z]+(-[a-z]+)*$"}}]}
               ]
             } =
               Parser.parser("validate(optional=[regex=^[a-z]+(-[a-z]+)*$])")
    end

    test "nested in either=[…, regex=…] alongside an atom op" do
      assert %{
               validate: [
                 %{either: [:integer, {:regex, %Regex{source: "^[A-Z]{2,}$"}}]}
               ]
             } =
               Parser.parser("validate(either=[integer, regex=^[A-Z]{2,}$])")
    end

    test "deep nest each[optional[regex]]" do
      assert %{
               validate: [
                 %{each: [%{optional: [{:regex, %Regex{source: "^[a-z]+$"}}]}]}
               ]
             } =
               Parser.parser("validate(each=[optional=[regex=^[a-z]+$]])")
    end

    test "long realistic pattern (URL with many query chars + sanitize ops + length cap)" do
      derive =
        "sanitize(trim, downcase) validate(string, not_empty, max_len=120, regex=^https?://[a-z0-9.-]+(:[0-9]+)?(/[a-z0-9._~%/?#@!$&'()*+,;=:-]*)?$)"

      assert %{
               sanitize: [:trim, :downcase],
               validate: [
                 :string,
                 :not_empty,
                 {:max_len, 120},
                 {:regex,
                  %Regex{
                    source:
                      "^https?://[a-z0-9.-]+(:[0-9]+)?(/[a-z0-9._~%/?#@!$&'()*+,;=:-]*)?$"
                  }}
               ]
             } = Parser.parser(derive)
    end

    test "literal-quoted pattern with embedded ] inside the quoted string" do
      assert %{validate: [{:regex, %Regex{source: "^a]b$"}}]} =
               Parser.parser(~S{validate(regex="^a]b$")})
    end
  end

  describe "direct ValidationDerive — accepts matching, rejects non-matching" do
    test "[a-z]+ accepts/rejects" do
      %{validate: [op]} = Parser.parser("validate(regex=^[a-z]+$)")
      assert "abc" == ValidationDerive.validate(op, "abc", :v)
      assert {:error, :v, :regex, "Invalid format in the v field"} =
               ValidationDerive.validate(op, "ABC", :v)
    end

    test "url-with-parens accepts http/https + optional port + optional path" do
      %{validate: [op]} =
        Parser.parser("validate(regex=^https?://[a-z0-9.-]+(:[0-9]+)?(/.*)?$)")

      assert "https://example.com" == ValidationDerive.validate(op, "https://example.com", :u)

      assert "http://example.com:8080/path" ==
               ValidationDerive.validate(op, "http://example.com:8080/path", :u)

      assert {:error, :u, :regex, "Invalid format in the u field"} =
               ValidationDerive.validate(op, "ftp://example.com", :u)

      assert {:error, :u, :regex, "Invalid format in the u field"} =
               ValidationDerive.validate(op, "example.com", :u)
    end

    test "lookahead password rejects without uppercase or digit" do
      %{validate: [op]} =
        Parser.parser("validate(regex=^(?=.*[A-Z])(?=.*\\d)[A-Za-z\\d]{8,}$)")

      assert "Hello123" == ValidationDerive.validate(op, "Hello123", :p)

      assert {:error, :p, :regex, "Invalid format in the p field"} =
               ValidationDerive.validate(op, "hello123", :p)

      assert {:error, :p, :regex, "Invalid format in the p field"} =
               ValidationDerive.validate(op, "HelloWorld", :p)

      assert {:error, :p, :regex, "Invalid format in the p field"} =
               ValidationDerive.validate(op, "Short1", :p)
    end

    test "ipv4-like accepts dotted quad, rejects non-numeric segments" do
      %{validate: [op]} =
        Parser.parser(
          "validate(regex=^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$)"
        )

      assert "192.168.0.1" == ValidationDerive.validate(op, "192.168.0.1", :ip)

      assert {:error, :ip, :regex, "Invalid format in the ip field"} =
               ValidationDerive.validate(op, "192.168.0", :ip)

      assert {:error, :ip, :regex, "Invalid format in the ip field"} =
               ValidationDerive.validate(op, "abc.168.0.1", :ip)
    end

    test "negated-class regex rejects strings containing a comma" do
      %{validate: [op]} = Parser.parser("validate(regex=^[^,]+$)")

      assert "no-commas-here" == ValidationDerive.validate(op, "no-commas-here", :s)

      assert {:error, :s, :regex, "Invalid format in the s field"} =
               ValidationDerive.validate(op, "has,comma", :s)
    end
  end

  describe "macro pipeline — builder/1 enforces the regex end-to-end" do
    test "WordsOnly accepts lowercase letters; rejects digits" do
      assert {:ok, %WordsOnly{value: "abc"}} = WordsOnly.builder(%{value: "abc"})

      assert {:error,
              [
                %{
                  field: :value,
                  action: :regex,
                  message: "Invalid format in the value field"
                }
              ]} = WordsOnly.builder(%{value: "abc123"})
    end

    test "DigitsOnly accepts digits; rejects mixed input" do
      assert {:ok, %DigitsOnly{value: "12345"}} = DigitsOnly.builder(%{value: "12345"})

      assert {:error,
              [
                %{
                  field: :value,
                  action: :regex,
                  message: "Invalid format in the value field"
                }
              ]} = DigitsOnly.builder(%{value: "12a45"})
    end

    test "EmailLike accepts well-formed email, rejects missing @" do
      assert {:ok, %EmailLike{value: "a@b.io"}} = EmailLike.builder(%{value: "a@b.io"})

      assert {:ok, %EmailLike{value: "user.name+tag@example.co.uk"}} =
               EmailLike.builder(%{value: "user.name+tag@example.co.uk"})

      assert {:error,
              [
                %{
                  field: :value,
                  action: :regex,
                  message: "Invalid format in the value field"
                }
              ]} = EmailLike.builder(%{value: "no-at-symbol"})
    end

    test "HexColor accepts #RRGGBB, rejects without hash" do
      assert {:ok, %HexColor{value: "#aBcDeF"}} = HexColor.builder(%{value: "#aBcDeF"})

      assert {:error,
              [
                %{field: :value, action: :regex, message: "Invalid format in the value field"}
              ]} = HexColor.builder(%{value: "aBcDeF"})
    end

    test "IPv4Like accepts dotted quad" do
      assert {:ok, %IPv4Like{value: "10.0.0.1"}} = IPv4Like.builder(%{value: "10.0.0.1"})

      assert {:error,
              [
                %{field: :value, action: :regex, message: "Invalid format in the value field"}
              ]} = IPv4Like.builder(%{value: "10.0.0"})
    end

    test "UrlWithParens accepts http/https with port and path" do
      assert {:ok, %UrlWithParens{value: "https://example.com"}} =
               UrlWithParens.builder(%{value: "https://example.com"})

      assert {:ok, %UrlWithParens{value: "http://example.com:8080/path"}} =
               UrlWithParens.builder(%{value: "http://example.com:8080/path"})

      assert {:error,
              [
                %{field: :value, action: :regex, message: "Invalid format in the value field"}
              ]} = UrlWithParens.builder(%{value: "ftp://example.com"})
    end

    test "NegatedClass — comma in input is rejected by ^[^,]+$" do
      assert {:ok, %NegatedClass{value: "no-commas-here"}} =
               NegatedClass.builder(%{value: "no-commas-here"})

      assert {:error,
              [
                %{field: :value, action: :regex, message: "Invalid format in the value field"}
              ]} = NegatedClass.builder(%{value: "has,comma"})
    end

    test "LookaheadPassword accepts mixed-case + digit + 8 chars" do
      assert {:ok, %LookaheadPassword{value: "Hello123"}} =
               LookaheadPassword.builder(%{value: "Hello123"})

      assert {:error,
              [
                %{field: :value, action: :regex, message: "Invalid format in the value field"}
              ]} = LookaheadPassword.builder(%{value: "hello"})
    end

    test "NestedEachRegex — every element is sanitized then regex-validated" do
      assert {:ok, %NestedEachRegex{tags: ["foo", "bar-baz"]}} =
               NestedEachRegex.builder(%{tags: ["  Foo  ", "  BAR-BAZ  ", "foo"]})

      # An element that survives sanitize but fails the regex (underscore not in set)
      assert {:error,
              [
                %{
                  field: :tags,
                  action: :regex,
                  __index__: 1,
                  message: "Invalid format in the tags field"
                }
              ]} = NestedEachRegex.builder(%{tags: ["good", "bad_one"]})
    end

    test "NestedOptionalRegex — nil passes, valid slug passes, bad slug fails" do
      assert {:ok, %NestedOptionalRegex{slug: nil}} =
               NestedOptionalRegex.builder(%{slug: nil})

      assert {:ok, %NestedOptionalRegex{slug: "valid-slug-name"}} =
               NestedOptionalRegex.builder(%{slug: "valid-slug-name"})

      assert {:error,
              [
                %{
                  field: :slug,
                  action: :regex,
                  message: "Invalid format in the slug field"
                }
              ]} = NestedOptionalRegex.builder(%{slug: "Not_A_Slug"})
    end

    test "EitherWithRegex — integer passes, uppercase string passes, lowercase fails" do
      assert {:ok, %EitherWithRegex{value: 42}} = EitherWithRegex.builder(%{value: 42})
      assert {:ok, %EitherWithRegex{value: "ABC"}} = EitherWithRegex.builder(%{value: "ABC"})

      assert {:error,
              [
                %{field: :value, action: :either, message: _}
              ]} = EitherWithRegex.builder(%{value: "abc"})
    end

    test "LongRealistic — full URL pipeline accepts well-formed, sanitizes case + trim" do
      assert {:ok, %LongRealistic{value: "https://example.com/path?q=1"}} =
               LongRealistic.builder(%{value: "  HTTPS://Example.com/path?q=1  "})

      assert {:error,
              [
                %{field: :value, action: :regex, message: "Invalid format in the value field"}
              ]} = LongRealistic.builder(%{value: "ftp://nope.com"})
    end
  end
end
