defmodule GuardedStructTest.ErrorsTest do
  use ExUnit.Case, async: true

  alias GuardedStruct.Errors
  alias GuardedStruct.Errors.{Invalid, Validation, Unknown}
  alias GuardedStructTest.Fixtures.Errors.SampleStruct

  test "wraps {:error, errors} into a Splode class" do
    {:error, errors} = SampleStruct.builder(%{email: "not-an-email", age: 200})

    class = Errors.from_tuple({:error, errors})

    assert %Invalid{} = class
    assert is_list(class.errors)
    assert Enum.all?(class.errors, &match?(%Validation{}, &1))
  end

  test "Validation exception carries field/action/message" do
    err = Validation.exception(field: :email, action: :email_r, message: "bad email")

    assert err.field == :email
    assert err.action == :email_r
    assert Exception.message(err) == "bad email"
  end

  test "from_tuple preserves the message text on each child error" do
    {:error, errors} = SampleStruct.builder(%{email: "x", age: 1})
    class = Errors.from_tuple(errors)

    messages = Enum.map(class.errors, & &1.message)
    assert Enum.any?(messages, &(&1 =~ "Incorrect email" or &1 =~ "Invalid"))
  end

  test "traverse_errors yields per-field error lists" do
    {:error, errors} = SampleStruct.builder(%{email: "x", age: -5})
    class = Errors.from_tuple(errors)

    grouped = Errors.traverse_errors(class, &Exception.message/1)
    assert is_map(grouped)
  end

  test "Unknown error wraps free-form payloads" do
    e = Unknown.exception(error: %{weird: 1}, message: "weird thing")
    assert Exception.message(e) == "weird thing"
  end
end
