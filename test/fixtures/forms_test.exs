defmodule GuardedStructFixtures.FormsTest do
  @moduledoc """
  Tests the `GuardedStructFixtures.Forms` fixture — covering:

    * `virtual_field` (`password_confirmation` validated but not on the struct)
    * Per-field `validator:` transforming the value (hashing)
    * `main_validator/1` auto-discovery (cross-field check)
    * `jason: true` (struct is `Jason.Encoder`-derived)
  """

  use ExUnit.Case, async: true

  alias GuardedStructFixtures.Forms

  describe "Signup happy paths" do
    test "hashes the password and matches confirmation" do
      # All required fields present, password matches confirmation.
      # Validator transforms plaintext → 64-char sha256 hex.
      # `:password_confirmation` is a virtual_field — validated but
      # never appears on the resulting struct.
      input = %{
        email: "  ALICE@example.COM  ",
        password: "hunter22!",
        password_confirmation: "hunter22!"
      }

      assert {:ok, signup} = Forms.Signup.builder(input)
      assert signup.email == "alice@example.com"
      assert String.length(signup.password) == 64

      refute Map.has_key?(signup, :password_confirmation)
    end

    test "sanitises the email (trim + downcase)" do
      # `:email` derives apply `sanitize(trim, downcase)` BEFORE
      # `validate(email_r)`, so whitespace + uppercase input is normalised.
      input = %{
        email: "  MIXEDcase@example.IO  ",
        password: "longenough",
        password_confirmation: "longenough"
      }

      assert {:ok, signup} = Forms.Signup.builder(input)
      assert signup.email == "mixedcase@example.io"
    end

    test "two different plaintext passwords produce different hashes" do
      # Sanity: the Hasher actually hashes — same email, different
      # passwords must yield different stored digests.
      input_a = %{email: "a@b.io", password: "passwordA", password_confirmation: "passwordA"}
      input_b = %{email: "a@b.io", password: "passwordB", password_confirmation: "passwordB"}

      {:ok, a} = Forms.Signup.builder(input_a)
      {:ok, b} = Forms.Signup.builder(input_b)

      assert a.password != b.password
    end
  end

  describe "Signup failure paths" do
    test "rejects mismatched confirmation via main_validator/1" do
      # ERROR REASON: `main_validator/1` is auto-discovered on the user
      # module. It re-hashes the virtual confirmation and compares to
      # the stored hash. Different plaintext → different hashes → mismatch.
      input = %{
        email: "alice@example.com",
        password: "hunter22!",
        password_confirmation: "different!"
      }

      assert {:error, errs} = Forms.Signup.builder(input)
      assert Enum.any?(errs, &(&1[:field] == :password_confirmation))
    end

    test "rejects short passwords via the Hasher length check" do
      # ERROR REASON: the validator (`Hasher.hash/2`) length-checks the
      # PLAINTEXT before hashing — "short" is 5 chars, below the 8-char
      # minimum. (`derives:` length checks run AFTER validators, so the
      # check has to live in the validator clause to see the raw input.)
      input = %{
        email: "alice@example.com",
        password: "short",
        password_confirmation: "short"
      }

      assert {:error, errs} = Forms.Signup.builder(input)
      errs = List.wrap(errs)
      assert Enum.any?(errs, &(&1[:field] == :password))
    end

    test "rejects when an enforced field is missing" do
      # ERROR REASON: `:password` and `:password_confirmation` are both
      # `enforce: true`. Only `:email` supplied → :required_fields error.
      assert {:error, _} = Forms.Signup.builder(%{email: "a@b.io"})
    end
  end

  describe "Full struct equality (deep map comparison)" do
    test "Signup.builder/1 returns the EXACT %Signup{} struct, every key asserted at once" do
      # Full deep-equality lock: every field must match in one ==.
      # Email is sanitised, password is the precomputed sha256 hex.
      hashed = :crypto.hash(:sha256, "longenough") |> Base.encode16(case: :lower)

      assert Forms.Signup.builder(%{
               email: "  ALICE@Example.IO  ",
               password: "longenough",
               password_confirmation: "longenough"
             }) ==
               {:ok,
                %Forms.Signup{
                  email: "alice@example.io",
                  password: hashed
                }}
    end

    test "Login.builder/1 returns the EXACT %Login{} struct" do
      # Login has no validator/transformer on `:password`, so the value
      # passes through unchanged. `:email` is still sanitised.
      assert Forms.Login.builder(%{
               email: "  USER@example.io  ",
               password: "anything"
             }) ==
               {:ok,
                %Forms.Login{
                  email: "user@example.io",
                  password: "anything"
                }}
    end
  end

  describe "Jason encoding (jason: true)" do
    test "Signup struct round-trips through Jason.encode!/1" do
      # `jason: true` derives `Jason.Encoder` on the struct AND any
      # generated sub_field submodules. Virtual fields are excluded
      # from the struct entirely, so they don't surface in the JSON.
      {:ok, signup} =
        Forms.Signup.builder(%{
          email: "a@b.io",
          password: "longenough",
          password_confirmation: "longenough"
        })

      json = Jason.encode!(signup)
      decoded = Jason.decode!(json)
      assert decoded["email"] == "a@b.io"
      refute Map.has_key?(decoded, "password_confirmation")
    end
  end

  describe "Login (no virtual fields)" do
    test "validates the inputs" do
      # Baseline happy path — both fields supplied, valid email.
      assert {:ok, _} = Forms.Login.builder(%{email: "x@y.io", password: "anything"})
    end

    test "rejects malformed email" do
      # ERROR REASON: `:email` derives include `validate(email_r)`.
      # "not-an-email" lacks the @-shape → :email_r action error.
      assert {:error, _} = Forms.Login.builder(%{email: "not-an-email", password: "x"})
    end
  end
end
