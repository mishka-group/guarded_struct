defmodule GuardedStructTest.ParserPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GuardedStruct.Derive.Parser

  describe "parser/1 never crashes" do
    property "any binary input returns nil or a map (never raises)" do
      check all(input <- StreamData.binary()) do
        result = Parser.parser(input)
        assert result == nil or is_map(result)
      end
    end

    property "any string with random ascii letters & digits returns nil or a map" do
      check all(
              input <-
                StreamData.string(:alphanumeric, max_length: 200)
            ) do
        result = Parser.parser(input)
        assert result == nil or is_map(result)
      end
    end

    property "input made of random op-shaped fragments doesn't crash" do
      atom_chars = StreamData.string([?a..?z, ?_], min_length: 1, max_length: 10)

      op_string =
        StreamData.bind(StreamData.list_of(atom_chars, min_length: 1, max_length: 5), fn args ->
          StreamData.member_of([
            "validate(#{Enum.join(args, ", ")})",
            "sanitize(#{Enum.join(args, ", ")})",
            "validate(#{Enum.join(args, ", ")}) sanitize(#{Enum.join(args, ", ")})"
          ])
        end)

      check all(input <- op_string) do
        result = Parser.parser(input)
        assert result == nil or is_map(result)
      end
    end
  end

  describe "parser/1 well-formed shapes" do
    property "valid sanitize+validate strings always parse to a map with the right keys" do
      ops_atom = StreamData.member_of([:trim, :upcase, :downcase, :capitalize, :strip_tags])

      validate_atom =
        StreamData.member_of([
          :string,
          :integer,
          :not_empty,
          :url,
          :uuid,
          :email_r,
          :ipv4
        ])

      check all(
              sanitize_ops <- StreamData.list_of(ops_atom, min_length: 1, max_length: 4),
              validate_ops <- StreamData.list_of(validate_atom, min_length: 1, max_length: 4)
            ) do
        input =
          "sanitize(#{Enum.join(sanitize_ops, ", ")}) " <>
            "validate(#{Enum.join(validate_ops, ", ")})"

        result = Parser.parser(input)
        assert is_map(result)

        assert Map.get(result, :sanitize) == sanitize_ops
        assert Map.get(result, :validate) == validate_ops
      end
    end

    property "validate(max_len=N) parses to {:max_len, N}" do
      check all(n <- StreamData.integer(0..1_000_000)) do
        result = Parser.parser("validate(max_len=#{n})")
        assert %{validate: [{:max_len, ^n}]} = result
      end
    end

    property "validate(min_len=N) parses to {:min_len, N}" do
      check all(n <- StreamData.integer(0..1_000_000)) do
        result = Parser.parser("validate(min_len=#{n})")
        assert %{validate: [{:min_len, ^n}]} = result
      end
    end
  end

  describe "parser/1 edge cases" do
    test "empty string" do
      assert Parser.parser("") == nil
    end

    test "nil" do
      assert Parser.parser(nil) == nil
    end

    test "list of inputs returns list of results" do
      assert [%{validate: [:string]}, nil] = Parser.parser(["validate(string)", ""])
    end

    test "missing closing paren is balanced" do
      assert %{sanitize: [:trim]} = Parser.parser("sanitize(trim")
    end

    test "missing closing paren on validate" do
      assert %{validate: [:string]} = Parser.parser("validate(string")
    end

    test "trailing whitespace doesn't break parsing" do
      assert %{validate: [:string]} = Parser.parser("validate(string)   ")
    end

    test "leading whitespace doesn't break parsing" do
      assert %{validate: [:string]} = Parser.parser("   validate(string)")
    end
  end
end
