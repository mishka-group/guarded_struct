defmodule GuardedStructTest.JsonEncoderTest do
  use ExUnit.Case, async: true

  # In this test env `:jason` is a dep, so `Jason.Encoder` wins the
  # precedence over the built-in `JSON.Encoder`. These tests verify the
  # Jason path. The built-in `JSON.Encoder` fallback is exercised in
  # downstream projects on Elixir 1.18+ that do NOT add Jason as a dep.

  alias GuardedStructTest.Fixtures.JsonEncoder.{Plain, WithJason, Nested}

  test "without json: true, no JSON encoder is derived" do
    {:ok, struct} = Plain.builder(%{name: "Alice", age: 30})

    assert_raise Protocol.UndefinedError, fn ->
      Jason.encode!(struct)
    end
  end

  test "with json: true, Jason.encode! works on the struct" do
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

  test "nested sub_field encodes recursively" do
    {:ok, struct} =
      Nested.builder(%{
        name: "Dave",
        address: %{city: "Berlin", zip: "10115"}
      })

    decoded = struct |> Jason.encode!() |> Jason.decode!()

    assert decoded["name"] == "Dave"
    assert decoded["address"]["city"] == "Berlin"
    assert decoded["address"]["zip"] == "10115"
  end
end
