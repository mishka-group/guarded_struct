defmodule GuardedStructTest.JasonEncoderTest do
  use ExUnit.Case, async: true

  defmodule Plain do
    use GuardedStruct

    guardedstruct do
      field(:name, String.t(), enforce: true)
      field(:age, integer())
    end
  end

  defmodule WithJason do
    use GuardedStruct

    guardedstruct jason: true do
      field(:name, String.t(), enforce: true)
      field(:age, integer())
    end
  end

  test "without jason: true, Jason.Encoder protocol is NOT derived" do
    {:ok, struct} = Plain.builder(%{name: "Alice", age: 30})

    assert_raise Protocol.UndefinedError, fn ->
      Jason.encode!(struct)
    end
  end

  test "with jason: true, Jason.encode! works on the struct" do
    {:ok, struct} = WithJason.builder(%{name: "Alice", age: 30})

    assert {:ok, json} = Jason.encode(struct)
    decoded = Jason.decode!(json)

    assert decoded["name"] == "Alice"
    assert decoded["age"] == 30
  end

  test "round-trip encode + decode preserves the field values" do
    {:ok, original} = WithJason.builder(%{name: "Bob", age: 22})

    json = Jason.encode!(original)
    decoded = Jason.decode!(json, keys: :atoms)

    assert decoded.name == "Bob"
    assert decoded.age == 22
  end

  test "nil fields encode as null" do
    {:ok, struct} = WithJason.builder(%{name: "Carol"})

    json = Jason.encode!(struct)
    assert json =~ "\"age\":null"
  end
end
