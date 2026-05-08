defmodule GuardedStructTest.VirtualFieldTest do
  use ExUnit.Case, async: true

  # `virtual_field` validates input but is NOT a member of the generated
  # struct. The classic use case is `password_confirm`: cross-field check
  # via `main_validator`, never persisted on the user struct.

  defmodule Signup do
    use GuardedStruct

    guardedstruct do
      field(:email, String.t(), enforce: true, derive: "validate(string, email_r)")
      field(:password, String.t(), enforce: true, derive: "validate(string, min_len=8)")
      virtual_field(:password_confirm, String.t(), derive: "validate(string)")
    end

    # Convention: `main_validator/1` is auto-discovered by the runtime when
    # defined on the user module (no need for an explicit MFA tuple in the
    # section opts).
    def main_validator(attrs) do
      if attrs[:password] == attrs[:password_confirm] do
        {:ok, attrs}
      else
        {:error, [%{field: :password_confirm, action: :match, message: "passwords don't match"}]}
      end
    end
  end

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

  defmodule WithDynamic do
    use GuardedStruct

    guardedstruct do
      field(:name, String.t(), enforce: true, derive: "validate(string)")
      dynamic_field(:metadata)
    end
  end

  test "dynamic_field defaults to %{} and accepts any map" do
    {:ok, %WithDynamic{name: "x", metadata: %{}}} = WithDynamic.builder(%{name: "x"})

    # Input map keys get atomized by the runtime regardless of value-side
    # contents, so a dynamic_field map ends up with all-atom keys.
    {:ok, %WithDynamic{metadata: %{a: 1, b: 2}}} =
      WithDynamic.builder(%{name: "x", metadata: %{"b" => 2, a: 1}})
  end

  test "dynamic_field rejects non-map" do
    {:error, errs} = WithDynamic.builder(%{name: "x", metadata: "not a map"})
    assert Enum.any?(errs, &match?(%{field: :metadata, action: :map}, &1))
  end
end
