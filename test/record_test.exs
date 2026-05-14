defmodule GuardedStructTest.RecordTest do
  use ExUnit.Case, async: true

  require Record
  Record.defrecord(:user, name: nil, age: nil)
  Record.defrecord(:address, street: nil, city: nil)

  alias GuardedStructTest.Fixtures.Record.WithRecord

  test ":record accepts any tagged tuple" do
    {:ok, %WithRecord{any_record: {:foo, 1, 2}}} =
      WithRecord.builder(%{any_record: {:foo, 1, 2}})

    {:ok, %WithRecord{any_record: {:bar, "x"}}} =
      WithRecord.builder(%{any_record: {:bar, "x"}})
  end

  test ":record rejects non-records" do
    {:error, errs} = WithRecord.builder(%{any_record: "not a tuple"})
    assert Enum.any?(errs, &match?(%{field: :any_record, action: :record}, &1))

    {:error, errs2} = WithRecord.builder(%{any_record: {1, 2, 3}})
    assert Enum.any?(errs2, &match?(%{field: :any_record, action: :record}, &1))
  end

  test "record=user accepts a real Record.defrecord-built record" do
    rec = user(name: "Alice", age: 30)
    assert {:ok, %WithRecord{user_record: ^rec}} = WithRecord.builder(%{user_record: rec})
  end

  test "record=user rejects records with the wrong tag" do
    addr = address(street: "Main", city: "NYC")
    {:error, errs} = WithRecord.builder(%{user_record: addr})
    assert Enum.any?(errs, &match?(%{field: :user_record, action: :record}, &1))
  end

  test "record=user rejects raw tagged tuples with the wrong tag" do
    {:error, _} = WithRecord.builder(%{user_record: {:not_user, "Alice", 30}})
  end

  test "Record accessors still work after validation" do
    rec = user(name: "Bob", age: 22)
    {:ok, %WithRecord{user_record: validated}} = WithRecord.builder(%{user_record: rec})

    assert user(validated, :name) == "Bob"
    assert user(validated, :age) == 22
  end
end
