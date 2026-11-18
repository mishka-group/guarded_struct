defmodule GuardedStructTest.ErrorsTest do
  use ExUnit.Case, async: true

  alias GuardedStruct.Errors
  alias GuardedStruct.Errors.{Invalid, Unknown, Validation}
  alias GuardedStructTest.Fixtures.Errors.SampleStruct

  test "wraps {:error, errors} into a Splode class" do
    {:error, errors} = SampleStruct.builder(%{email: "not-an-email", age: 200})

    class = Errors.from_tuple({:error, errors})

    assert %Invalid{
             errors: [
               %Validation{field: :email, action: :email_r},
               %Validation{field: :age, action: :max_len}
             ]
           } = class
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

    assert [%Validation{field: :email, message: message}] = class.errors
    assert message =~ "Incorrect email"
  end

  test "traverse_errors yields per-field error lists" do
    {:error, errors} = SampleStruct.builder(%{email: "x", age: -5})
    class = Errors.from_tuple(errors)

    # Top-level fields share the root path `[]`.
    assert %{[] => [email_message, age_message]} =
             Errors.traverse_errors(class, &Exception.message/1)

    assert email_message =~ "Incorrect email"
    assert age_message =~ "minimum number the age field is 0"
  end

  test "Unknown error wraps free-form payloads" do
    e = Unknown.exception(error: %{weird: 1}, message: "weird thing")
    assert Exception.message(e) == "weird thing"
  end

  test "a nested struct's errors become child errors of its field" do
    error =
      GuardedStruct.Errors.from_tuple(
        {:error, [%{field: :items, errors: [%{field: :amount, action: :price, message: "bad"}]}]}
      )

    assert %GuardedStruct.Errors.Invalid{
             errors: [
               %GuardedStruct.Errors.Validation{
                 field: :items,
                 action: :nested,
                 child_errors: [%GuardedStruct.Errors.Validation{field: :amount, action: :price}]
               }
             ]
           } = error
  end
end
