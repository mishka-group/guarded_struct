defmodule GuardedStructTest.VirtualFieldTest do
  use ExUnit.Case, async: true

  # `virtual_field` validates input but is NOT a member of the generated
  # struct. The classic use case is `password_confirm`: cross-field check
  # via `main_validator`, never persisted on the user struct.

  alias GuardedStructTest.Fixtures.VirtualField.{Signup, WithDynamic}

  test "virtual fields are validated and visible to main_validator" do
    assert {:ok, %Signup{} = s} =
             Signup.builder(%{
               email: "u@example.com",
               password: "longpassword",
               password_confirm: "longpassword"
             })

    # Not on the struct.
    refute Map.has_key?(s, :password_confirm)
    assert s.password == "longpassword"
  end

  test "virtual field validation failure surfaces" do
    {:error, errs} =
      Signup.builder(%{
        email: "u@example.com",
        password: "longpassword",
        password_confirm: "differentlongpw"
      })

    assert Enum.any?(errs, &match?(%{field: :password_confirm, action: :match}, &1))
  end

  test "virtual field NOT in keys/0" do
    refute :password_confirm in Signup.keys()
    assert :email in Signup.keys()
    assert :password in Signup.keys()
  end

  test "dynamic_field defaults to %{} and accepts any map" do
    {:ok, %WithDynamic{name: "x", metadata: %{}}} = WithDynamic.builder(%{name: "x"})

    # SECURITY: dynamic_field values are LEFT AS-IS — string keys stay as
    # strings, atom keys stay as atoms, mixed stays mixed. This prevents
    # atom-table-exhaustion DoS via attacker-controlled keys. See SECURITY.md.
    {:ok, %WithDynamic{metadata: %{:a => 1, "b" => 2}}} =
      WithDynamic.builder(%{name: "x", metadata: %{"b" => 2, a: 1}})
  end

  test "dynamic_field rejects non-map" do
    {:error, errs} = WithDynamic.builder(%{name: "x", metadata: "not a map"})
    assert Enum.any?(errs, &match?(%{field: :metadata, action: :map}, &1))
  end
end
