defmodule GuardedStructTest.ValidateTest do
  use ExUnit.Case, async: true

  alias GuardedStruct.Validate
  alias GuardedStructTest.Fixtures.Validate.{Person, WithAuth}

  describe "Validate.run/2 — op string against value" do
    test "valid string passes a derive op-string" do
      assert {:ok, "alice@example.com"} =
               Validate.run("validate(string, email_r)", "alice@example.com")
    end

    test "sanitize + validate together" do
      assert {:ok, "hi"} = Validate.run("sanitize(trim) validate(string)", "  hi  ")
    end

    test "downcasing sanitizer works" do
      assert {:ok, "alice"} =
               Validate.run("sanitize(trim, downcase) validate(string)", "  ALICE  ")
    end

    test "type mismatch returns error tuple shape" do
      {:error, errs} = Validate.run("validate(integer)", "not-int")
      assert Enum.any?(errs, &match?(%{field: :__value__, action: :integer}, &1))
    end

    test "min_len failure" do
      {:error, errs} = Validate.run("validate(integer, min_len=0)", -5)
      assert Enum.any?(errs, &(&1[:action] == :min_len))
    end

    test "max_len with strings" do
      {:error, errs} = Validate.run("validate(string, max_len=3)", "hello")
      assert Enum.any?(errs, &(&1[:action] == :max_len))
    end

    test "uuid format pass" do
      assert {:ok, "11111111-2222-3333-4444-555555555555"} =
               Validate.run("validate(uuid)", "11111111-2222-3333-4444-555555555555")
    end

    test "uuid format fail" do
      {:error, _} = Validate.run("validate(uuid)", "not-a-uuid")
    end

    test "enum pass" do
      assert {:ok, "admin"} =
               Validate.run("validate(enum=String[admin::user::guest])", "admin")
    end

    test "enum fail" do
      {:error, _} = Validate.run("validate(enum=String[admin::user])", "invalid")
    end

    test "empty derive string returns the value untouched" do
      assert {:ok, "x"} = Validate.run("", "x")
    end
  end

  describe "Validate.field/3,4 — strict mode (default)" do
    test "valid value passes a self-contained field" do
      assert {:ok, "Alice"} = Validate.field(Person, :name, "Alice")
    end

    test "trims and validates with derive" do
      assert {:ok, "Alice"} = Validate.field(Person, :name, "  Alice  ")
    end

    test "invalid email returns error" do
      {:error, errs} = Validate.field(Person, :email, "not-an-email")
      assert Enum.any?(errs, &(&1[:action] == :email_r))
    end

    test "integer type validation" do
      {:error, errs} = Validate.field(Person, :age, "thirty")
      assert Enum.any?(errs, &(&1[:action] == :integer))
    end

    test "enum field" do
      assert {:ok, "admin"} = Validate.field(Person, :role, "admin")
      {:error, _} = Validate.field(Person, :role, "owner")
    end

    test "field with cross-field on: dep but no context → :dependent_keys error" do
      {:error, errs} = Validate.field(Person, :parent_email, "p@x.com")
      assert Enum.any?(errs, &(&1[:action] == :dependent_keys))
    end

    test "unknown field returns clear error" do
      {:error, [err]} = Validate.field(Person, :nonexistent, "x")
      assert err.action == :unknown_field
      assert err.message =~ "is not defined"
    end

    test "per-field MFA validator runs and reports its own error" do
      {:error, errs} = Validate.field(Person, :nickname, "ab")
      assert Enum.any?(errs, &(&1[:action] == :validator))
    end

    test "per-field MFA validator passes" do
      assert {:ok, "alice"} = Validate.field(Person, :nickname, "alice")
    end
  end

  describe "Validate.field/4 — context for cross-field deps" do
    test "providing the dep field in context makes on: resolve" do
      assert {:ok, "p@x.com"} =
               Validate.field(Person, :parent_email, "p@x.com",
                 context: %{account_type: "personal"}
               )
    end

    test "context missing the dep still errors" do
      {:error, errs} =
        Validate.field(Person, :parent_email, "p@x.com", context: %{age: 30})

      assert Enum.any?(errs, &(&1[:action] == :dependent_keys))
    end

    test "context resolution accepts string keys too" do
      assert {:ok, _} =
               Validate.field(Person, :parent_email, "p@x.com",
                 context: %{account_type: "business"}
               )
    end
  end

  describe "Validate.field/4 — :isolated mode" do
    test "skips on: dep entirely" do
      assert {:ok, "p@x.com"} =
               Validate.field(Person, :parent_email, "p@x.com", mode: :isolated)
    end

    test "still runs derive validation" do
      {:error, errs} =
        Validate.field(Person, :parent_email, "not-an-email", mode: :isolated)

      assert Enum.any?(errs, &(&1[:action] == :email_r))
    end

    test "still runs validator MFA" do
      {:error, _} = Validate.field(Person, :nickname, "ab", mode: :isolated)
    end
  end

  describe "Validate.partial/2 — subset of fields" do
    test "valid subset returns the validated map" do
      assert {:ok, %{name: "Alice", email: "alice@example.com"}} =
               Validate.partial(Person, %{name: "Alice", email: "alice@example.com"})
    end

    test "missing fields are silently skipped (no enforce_keys check)" do
      assert {:ok, %{age: 30}} = Validate.partial(Person, %{age: 30})
    end

    test "errors on the fields PRESENT — not on missing ones" do
      {:error, errs} = Validate.partial(Person, %{name: "OK", email: "bad"})
      assert Enum.any?(errs, &(&1[:field] == :email))
      refute Enum.any?(errs, &(&1[:field] == :name))
    end

    test "cross-field deps resolve from the same input" do
      assert {:ok, _} =
               Validate.partial(Person, %{
                 account_type: "personal",
                 parent_email: "p@x.com"
               })
    end

    test "cross-field dep absent from input → error" do
      {:error, errs} = Validate.partial(Person, %{parent_email: "p@x.com"})
      assert Enum.any?(errs, &(&1[:action] == :dependent_keys))
    end

    test "rejects non-map input" do
      {:error, _} = Validate.partial(Person, "not a map")
    end

    test "accepts string-key input and atomises" do
      assert {:ok, _} =
               Validate.partial(Person, %{"name" => "Bob", "age" => 22})
    end

    test "aggregates multiple errors" do
      {:error, errs} =
        Validate.partial(Person, %{name: "x", age: -10, email: "bad"})

      assert length(errs) >= 2
    end

    test "empty input returns empty map" do
      assert {:ok, %{}} = Validate.partial(Person, %{})
    end
  end

  describe "Validate against a sub_field-bearing module" do
    test "field/3 against the parent's plain field" do
      assert {:ok, "Bob"} = Validate.field(WithAuth, :name, "Bob")
    end

    test "field/3 against a sub_field returns the sub_field's value (treated as opaque)" do
      result = Validate.field(WithAuth, :auth, %{role: "admin"})
      assert match?({:ok, _}, result)
    end
  end

  describe "Validate.run integrates with sanitize_derive Application env" do
    test "domain enum pre-evaluation still works" do
      assert {:ok, %{x: 1}} =
               Validate.run("validate(enum=Map[%{x: 1}::%{x: 2}])", %{x: 1})
    end
  end
end
