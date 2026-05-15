defmodule GuardedStructTest.Property.DerivePipelineTest do
  @moduledoc """
  Properties of the sanitize / validate pipeline.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GuardedStruct.Derive.{SanitizerDerive, ValidationDerive, Parser}

  describe "sanitizer idempotence" do
    property "trim applied twice equals trim applied once (binary inputs)" do
      check all(input <- StreamData.binary()) do
        once = SanitizerDerive.sanitize(:trim, input)
        twice = SanitizerDerive.sanitize(:trim, once)
        assert once == twice
      end
    end

    property "downcase applied twice equals downcase applied once" do
      check all(input <- StreamData.string(:printable)) do
        once = SanitizerDerive.sanitize(:downcase, input)
        twice = SanitizerDerive.sanitize(:downcase, once)
        assert once == twice
      end
    end

    property "upcase applied twice equals upcase applied once" do
      check all(input <- StreamData.string(:printable)) do
        once = SanitizerDerive.sanitize(:upcase, input)
        twice = SanitizerDerive.sanitize(:upcase, once)
        assert once == twice
      end
    end

    property "non-string inputs are passed through untouched by string sanitizers" do
      check all(
              input <-
                StreamData.one_of([
                  StreamData.integer(),
                  StreamData.float(),
                  StreamData.boolean(),
                  StreamData.list_of(StreamData.integer())
                ])
            ) do
        assert SanitizerDerive.sanitize(:trim, input) == input
        assert SanitizerDerive.sanitize(:downcase, input) == input
        assert SanitizerDerive.sanitize(:upcase, input) == input
      end
    end
  end

  describe "sanitizer order independence (commutative pairs)" do
    property "trim ∘ downcase ≡ downcase ∘ trim on printable strings" do
      check all(input <- StreamData.string(:printable)) do
        a = SanitizerDerive.sanitize(:downcase, SanitizerDerive.sanitize(:trim, input))
        b = SanitizerDerive.sanitize(:trim, SanitizerDerive.sanitize(:downcase, input))
        assert a == b
      end
    end
  end

  describe "trim contract" do
    property "trimmed binary has no leading or trailing whitespace" do
      check all(input <- StreamData.binary(max_length: 200)) do
        case SanitizerDerive.sanitize(:trim, input) do
          out when is_binary(out) ->
            refute String.starts_with?(out, [" ", "\t", "\n", "\r"])
            refute String.ends_with?(out, [" ", "\t", "\n", "\r"])

          _ ->
            :ok
        end
      end
    end
  end

  describe "ValidationDerive.call/3" do
    property "min_len classifier matches String.length on binary inputs" do
      check all(
              input <- StreamData.string(:alphanumeric, max_length: 50),
              min <- StreamData.integer(0..30)
            ) do
        {_processed, errors} =
          ValidationDerive.call({:test, input}, [{:min_len, min}], [])

        actual_len = String.length(input)

        cond do
          actual_len >= min ->
            assert errors == []

          true ->
            assert Enum.any?(errors, &match?(%{action: :min_len}, &1))
        end
      end
    end

    property "max_len classifier matches String.length on binary inputs" do
      check all(
              input <- StreamData.string(:alphanumeric, max_length: 50),
              max <- StreamData.integer(0..50)
            ) do
        {_processed, errors} =
          ValidationDerive.call({:test, input}, [{:max_len, max}], [])

        actual_len = String.length(input)

        cond do
          actual_len <= max ->
            assert errors == []

          true ->
            assert Enum.any?(errors, &match?(%{action: :max_len}, &1))
        end
      end
    end

    property "integer validator rejects every non-integer atomic shape" do
      check all(
              input <-
                StreamData.one_of([
                  StreamData.string(:alphanumeric),
                  StreamData.float(),
                  StreamData.boolean(),
                  StreamData.constant(nil)
                ])
            ) do
        {_processed, errors} =
          ValidationDerive.call({:n, input}, [:integer], [])

        assert Enum.any?(errors, &match?(%{action: :integer}, &1))
      end
    end

    property "integer validator accepts every integer" do
      check all(input <- StreamData.integer()) do
        {_processed, errors} =
          ValidationDerive.call({:n, input}, [:integer], [])

        assert errors == []
      end
    end
  end

  describe "parser stability" do
    property "parsing a well-formed sanitize+validate string yields the declared op atoms" do
      sanitizers = StreamData.member_of([:trim, :upcase, :downcase, :capitalize])
      validators = StreamData.member_of([:string, :not_empty, :integer])

      check all(
              s_ops <- StreamData.list_of(sanitizers, min_length: 1, max_length: 4),
              v_ops <- StreamData.list_of(validators, min_length: 1, max_length: 4)
            ) do
        str =
          "sanitize(" <>
            Enum.join(s_ops, ", ") <>
            ") validate(" <> Enum.join(v_ops, ", ") <> ")"

        result = Parser.parser(str)

        assert is_map(result)
        assert Map.fetch!(result, :sanitize) == s_ops
        assert Map.fetch!(result, :validate) == v_ops
      end
    end
  end
end
