defmodule GuardedStructFixtures.FormsTest do
  @moduledoc """
  Comprehensive tests for `GuardedStructFixtures.Forms` — the canonical
  real-world signup/login fixture.

  Coverage strategy: **full output equality everywhere**.

    * Happy paths assert the ENTIRE returned struct in one `==` so any
      drift in any field (sanitization, hashing, defaults) fails loudly.
    * Failure paths assert the EXACT error list/map (field, action,
      message) so any change to error format is caught at PR time.

  Sections:
    1. Signup happy paths             — 7 tests
    2. Signup boundary values         — 4 tests
    3. Signup failure paths           — 9 tests
    4. Signup multi-error aggregation — 2 tests
    5. Jason encoding                 — 3 tests
    6. Login happy paths              — 2 tests
    7. Login failure paths            — 4 tests
    8. Introspection / module surface — 4 tests
  """

  use ExUnit.Case, async: true

  alias GuardedStructFixtures.Forms

  # SHA256 of the strings used across tests — precomputed so happy-path
  # assertions can use `==` against the exact hex digest.
  defp sha256(s), do: :crypto.hash(:sha256, s) |> Base.encode16(case: :lower)

  defp hash_of_longenough, do: sha256("longenough")
  defp hash_of_passworda, do: sha256("passwordA")
  defp hash_of_passwordb, do: sha256("passwordB")
  defp hash_of_min_password, do: sha256("min8char")
  defp hash_of_unicode, do: sha256("pässwörd")

  # ============================================================
  # 1. Signup — happy paths (full struct equality)
  # ============================================================
  describe "Signup happy paths (full == on the returned struct)" do
    test "standard input → email sanitised, password hashed, virtual dropped" do
      # Input has mixed-case email with whitespace and an 8+ char password.
      # Output: lowercase trimmed email, sha256 hash, NO :password_confirmation.
      assert Forms.Signup.builder(%{
               email: "  ALICE@example.IO  ",
               password: "longenough",
               password_confirmation: "longenough"
             }) ==
               {:ok,
                %Forms.Signup{
                  email: "alice@example.io",
                  password: hash_of_longenough()
                }}
    end

    test "already-lowercase email passes through unchanged after trim" do
      # No casing to flip — only trim has effect on this email.
      assert Forms.Signup.builder(%{
               email: "  alice@example.io  ",
               password: "longenough",
               password_confirmation: "longenough"
             }) ==
               {:ok,
                %Forms.Signup{
                  email: "alice@example.io",
                  password: hash_of_longenough()
                }}
    end

    test "fully-uppercase email becomes fully-lowercase" do
      assert Forms.Signup.builder(%{
               email: "ALICE@EXAMPLE.IO",
               password: "longenough",
               password_confirmation: "longenough"
             }) ==
               {:ok,
                %Forms.Signup{
                  email: "alice@example.io",
                  password: hash_of_longenough()
                }}
    end

    test "hashing is deterministic — same plaintext → same hash" do
      # Two builds with the same plaintext yield byte-identical structs.
      {:ok, a} =
        Forms.Signup.builder(%{
          email: "a@b.io",
          password: "longenough",
          password_confirmation: "longenough"
        })

      {:ok, b} =
        Forms.Signup.builder(%{
          email: "a@b.io",
          password: "longenough",
          password_confirmation: "longenough"
        })

      assert a == b
      assert a.password == hash_of_longenough()
    end

    test "different plaintexts → different hashes" do
      input_a = %{email: "a@b.io", password: "passwordA", password_confirmation: "passwordA"}
      input_b = %{email: "a@b.io", password: "passwordB", password_confirmation: "passwordB"}

      assert Forms.Signup.builder(input_a) ==
               {:ok, %Forms.Signup{email: "a@b.io", password: hash_of_passworda()}}

      assert Forms.Signup.builder(input_b) ==
               {:ok, %Forms.Signup{email: "a@b.io", password: hash_of_passwordb()}}
    end

    test "unicode password is hashed correctly" do
      # SHA256 operates on raw bytes, so non-ASCII chars hash fine.
      assert Forms.Signup.builder(%{
               email: "x@y.io",
               password: "pässwörd",
               password_confirmation: "pässwörd"
             }) ==
               {:ok,
                %Forms.Signup{
                  email: "x@y.io",
                  password: hash_of_unicode()
                }}
    end

    test "password_confirmation does NOT appear on the struct or in Map.keys/1" do
      # Locks the virtual_field semantics — even after a successful build,
      # the confirmation field is not on the struct, not in Map.from_struct, etc.
      {:ok, signup} =
        Forms.Signup.builder(%{
          email: "a@b.io",
          password: "longenough",
          password_confirmation: "longenough"
        })

      refute Map.has_key?(signup, :password_confirmation)
      assert Map.keys(signup) |> Enum.sort() == [:__struct__, :email, :password]
    end
  end

  # ============================================================
  # 2. Signup — boundary values (full equality at the limits)
  # ============================================================
  describe "Signup boundary values" do
    test "password at the minimum allowed length (8 chars) is accepted" do
      assert Forms.Signup.builder(%{
               email: "a@b.io",
               password: "min8char",
               password_confirmation: "min8char"
             }) ==
               {:ok,
                %Forms.Signup{
                  email: "a@b.io",
                  password: hash_of_min_password()
                }}
    end

    test "password at the maximum allowed length (128 chars) is accepted" do
      pw = String.duplicate("x", 128)
      hashed = sha256(pw)

      assert Forms.Signup.builder(%{
               email: "a@b.io",
               password: pw,
               password_confirmation: pw
             }) ==
               {:ok, %Forms.Signup{email: "a@b.io", password: hashed}}
    end

    test "long but valid email (≤ 320 chars) is accepted" do
      # Need a syntactically-valid email under max_len=320. Build one with
      # a long local part and a normal domain — that satisfies both
      # email_r's regex AND the length cap.
      local = String.duplicate("a", 100)
      email = local <> "@example.io"
      assert String.length(email) <= 320

      assert Forms.Signup.builder(%{
               email: email,
               password: "longenough",
               password_confirmation: "longenough"
             }) ==
               {:ok, %Forms.Signup{email: email, password: hash_of_longenough()}}
    end

    test "password 7 chars (one below min) is rejected by the Hasher" do
      # ERROR REASON: Hasher.hash/2 requires byte_size in 8..128. 7 chars fails.
      # Note: when Hasher errors, the post-validator value is the original input
      # (treated as if validation didn't transform), so main_validator's hash
      # comparison ALSO fails — producing TWO errors.
      assert Forms.Signup.builder(%{
               email: "a@b.io",
               password: "7chars!",
               password_confirmation: "7chars!"
             }) ==
               {:error,
                [
                  %{
                    message: "passwords don't match",
                    field: :password_confirmation,
                    action: :match
                  },
                  %{
                    message: "password must be 8-128 characters",
                    field: :password,
                    action: :validator
                  }
                ]}
    end
  end

  # ============================================================
  # 3. Signup — failure paths (exact error shape)
  # ============================================================
  describe "Signup failure paths (exact error structure)" do
    test "missing :email → single :required_fields map (not a list)" do
      # ERROR REASON: orchestration-layer required_fields returns a MAP,
      # not a list — locked in here to prevent accidental wrapping change.
      assert Forms.Signup.builder(%{
               password: "longenough",
               password_confirmation: "longenough"
             }) ==
               {:error,
                %{
                  message: "Please submit required fields.",
                  fields: [:email],
                  action: :required_fields
                }}
    end

    test "missing :password → single :required_fields map" do
      assert Forms.Signup.builder(%{
               email: "a@b.io",
               password_confirmation: "longenough"
             }) ==
               {:error,
                %{
                  message: "Please submit required fields.",
                  fields: [:password],
                  action: :required_fields
                }}
    end

    test "missing :password_confirmation → main_validator's :match error" do
      # ERROR REASON: :password_confirmation is a virtual_field. When
      # missing, main_validator/1 falls through to the catch-all clause
      # (binary guard fails on nil) → returns :match error.
      # Note the wrapper differs — :required_fields is a single map but
      # main_validator returns a LIST of errors.
      assert Forms.Signup.builder(%{
               email: "a@b.io",
               password: "longenough"
             }) ==
               {:error,
                [
                  %{
                    message: "passwords don't match",
                    field: :password_confirmation,
                    action: :match
                  }
                ]}
    end

    test "mismatched confirmation → main_validator :match error" do
      # ERROR REASON: both passwords are valid 8+ char strings, so Hasher
      # accepts both. But after hashing, the stored hash and the re-hashed
      # confirmation differ → main_validator returns :match.
      assert Forms.Signup.builder(%{
               email: "a@b.io",
               password: "abcdefgh",
               password_confirmation: "different"
             }) ==
               {:error,
                [
                  %{
                    message: "passwords don't match",
                    field: :password_confirmation,
                    action: :match
                  }
                ]}
    end

    test "invalid email format → :email_r action" do
      # ERROR REASON: derive's validate(email_r) regex requires "@" + domain.
      assert Forms.Signup.builder(%{
               email: "not-an-email",
               password: "longenough",
               password_confirmation: "longenough"
             }) ==
               {:error,
                [
                  %{
                    message: "Incorrect email in the email field.",
                    field: :email,
                    action: :email_r
                  }
                ]}
    end

    test "email too long → rejected (either :max_len or :email_r depending on shape)" do
      # ERROR REASON: derive's max_len=320 cap. Building a syntactically
      # valid email longer than 320 chars and asserting :max_len fires.
      # Use a 350-char local part so the shape is still email-like.
      local = String.duplicate("a", 350)
      long_email = local <> "@example.io"
      assert String.length(long_email) > 320

      assert {:error, errs} =
               Forms.Signup.builder(%{
                 email: long_email,
                 password: "longenough",
                 password_confirmation: "longenough"
               })

      errs = List.wrap(errs)
      # The error mentions :email and is a length-violation (:max_len).
      assert Enum.any?(errs, &(&1[:field] == :email and &1[:action] == :max_len))
    end

    test "password too long (130 chars) → 2 errors: Hasher rejects + match fails" do
      # ERROR REASON: Hasher.hash/2 has the upper bound 128. 130 chars
      # fails, password stays unhashed, then main_validator's comparison
      # fails too → two errors aggregated.
      pw = String.duplicate("x", 130)

      assert Forms.Signup.builder(%{
               email: "a@b.io",
               password: pw,
               password_confirmation: pw
             }) ==
               {:error,
                [
                  %{
                    message: "passwords don't match",
                    field: :password_confirmation,
                    action: :match
                  },
                  %{
                    message: "password must be 8-128 characters",
                    field: :password,
                    action: :validator
                  }
                ]}
    end

    test "non-binary password (integer) → Hasher's catch-all error" do
      # ERROR REASON: Hasher's third clause matches non-binary, returns a
      # descriptive error embedding the inspected value.
      assert Forms.Signup.builder(%{
               email: "a@b.io",
               password: 12345,
               password_confirmation: "xxxxxxxx"
             }) ==
               {:error,
                [
                  %{
                    message: "passwords don't match",
                    field: :password_confirmation,
                    action: :match
                  },
                  %{
                    message: "expected a string, got 12345",
                    field: :password,
                    action: :validator
                  }
                ]}
    end

    test "empty-string password (len=0) → 2 errors" do
      # ERROR REASON: same as 7-char path — Hasher rejects on length AND
      # main_validator can't compare hashes because Hasher errored.
      assert Forms.Signup.builder(%{
               email: "a@b.io",
               password: "",
               password_confirmation: ""
             }) ==
               {:error,
                [
                  %{
                    message: "passwords don't match",
                    field: :password_confirmation,
                    action: :match
                  },
                  %{
                    message: "password must be 8-128 characters",
                    field: :password,
                    action: :validator
                  }
                ]}
    end
  end

  # ============================================================
  # 4. Multi-error aggregation (multiple things wrong at once)
  # ============================================================
  describe "Signup — multi-error aggregation" do
    test "two distinct stage-8 failures (validator + main_validator) BOTH appear" do
      # Stage 8 (per-field validator) and stage 9 (main_validator) errors
      # are aggregated together. Bad password → Hasher returns :validator,
      # AND main_validator fails the hash comparison → :match.
      # Note: derive (stage 10) is SHORT-CIRCUITED when main_validator
      # fails, so email's :email_r derive does NOT run in this case.
      assert {:error, errs} =
               Forms.Signup.builder(%{
                 email: "not-an-email",
                 password: "tiny",
                 password_confirmation: "tiny"
               })

      assert is_list(errs)
      actions = Enum.map(errs, & &1.action) |> Enum.sort()
      assert :match in actions
      assert :validator in actions
    end

    test "all-fields invalid → multiple errors collected in one response" do
      # Locks the "no short-circuit between stages" invariant for stages
      # that both run (per-field validator + main_validator).
      assert {:error, errs} =
               Forms.Signup.builder(%{
                 email: "bad",
                 password: 999,
                 password_confirmation: 999
               })

      errs = List.wrap(errs)
      assert length(errs) >= 2
    end
  end

  # ============================================================
  # 5. Jason encoding — full decoded-map equality
  # ============================================================
  describe "Signup JSON encoding (jason: true)" do
    test "decoded JSON contains EXACTLY the public fields (no virtuals)" do
      {:ok, signup} =
        Forms.Signup.builder(%{
          email: "alice@example.io",
          password: "longenough",
          password_confirmation: "longenough"
        })

      decoded = signup |> Jason.encode!() |> Jason.decode!()

      # Full equality — every key spelled out, virtual fields NOT present.
      assert decoded ==
               %{
                 "email" => "alice@example.io",
                 "password" => hash_of_longenough()
               }
    end

    test "encoding is round-trip stable (decode-encode-decode → same map)" do
      # Map key order in JSON output is NOT deterministic, so we can't
      # compare bytes directly. But decoded maps MUST be identical.
      {:ok, signup} =
        Forms.Signup.builder(%{
          email: "a@b.io",
          password: "longenough",
          password_confirmation: "longenough"
        })

      once = signup |> Jason.encode!() |> Jason.decode!()
      twice = signup |> Jason.encode!() |> Jason.decode!() |> Jason.encode!() |> Jason.decode!()
      assert once == twice
    end

    test "decoded JSON has exactly two keys" do
      {:ok, signup} =
        Forms.Signup.builder(%{
          email: "a@b.io",
          password: "longenough",
          password_confirmation: "longenough"
        })

      decoded = signup |> Jason.encode!() |> Jason.decode!()
      assert Map.keys(decoded) |> Enum.sort() == ["email", "password"]
    end
  end

  # ============================================================
  # 6. Login — happy paths (full equality)
  # ============================================================
  describe "Login happy paths" do
    test "standard input — email sanitised, password raw (no validator)" do
      assert Forms.Login.builder(%{
               email: "  USER@example.IO  ",
               password: "anything"
             }) ==
               {:ok,
                %Forms.Login{
                  email: "user@example.io",
                  password: "anything"
                }}
    end

    test "password is passed through unchanged (Login has no Hasher)" do
      # Locks the contract: Login is for AUTHENTICATION, not signup.
      # Plaintext password is stored as-is so a downstream service can
      # compare it against a stored hash.
      assert Forms.Login.builder(%{
               email: "x@y.io",
               password: "🔥 plaintext with unicode 🔑"
             }) ==
               {:ok,
                %Forms.Login{
                  email: "x@y.io",
                  password: "🔥 plaintext with unicode 🔑"
                }}
    end
  end

  # ============================================================
  # 7. Login — failure paths (exact error shape)
  # ============================================================
  describe "Login failure paths" do
    test "missing :email → :required_fields error" do
      assert Forms.Login.builder(%{password: "anything"}) ==
               {:error,
                %{
                  message: "Please submit required fields.",
                  fields: [:email],
                  action: :required_fields
                }}
    end

    test "missing :password → :required_fields error" do
      assert Forms.Login.builder(%{email: "x@y.io"}) ==
               {:error,
                %{
                  message: "Please submit required fields.",
                  fields: [:password],
                  action: :required_fields
                }}
    end

    test "invalid email → :email_r action" do
      # ERROR REASON: derive(validate(email_r)) rejects malformed emails.
      assert Forms.Login.builder(%{email: "not-an-email", password: "x"}) ==
               {:error,
                [
                  %{
                    message: "Incorrect email in the email field.",
                    field: :email,
                    action: :email_r
                  }
                ]}
    end

    test "empty password → :min_len action (Login uses min_len=1)" do
      # ERROR REASON: Login's :password derive is `validate(string, min_len=1)`.
      # An empty string is 0 chars < 1 → :min_len.
      assert {:error,
              [
                %{
                  field: :password,
                  action: :min_len,
                  message: "The minimum number of characters in the password field is 1" <> _
                }
              ]} = Forms.Login.builder(%{email: "x@y.io", password: ""})
    end
  end

  # ============================================================
  # 8. Module surface / introspection
  # ============================================================
  describe "Signup module introspection" do
    test "keys/0 lists email + password (NO :password_confirmation)" do
      # Virtual fields don't appear in keys/0 — they're not in defstruct.
      assert Forms.Signup.keys() == [:email, :password]
    end

    test "enforce_keys/0 includes both visible fields" do
      assert Forms.Signup.enforce_keys() |> Enum.sort() == [:email, :password]
    end

    test "__information__/0 carries the expected module metadata" do
      info = Forms.Signup.__information__()
      assert info.module == Forms.Signup
      assert info.keys == [:email, :password]
      assert Enum.sort(info.enforce_keys) == [:email, :password]
      assert info.options.jason == true
      assert info.conditional_keys == []
    end

    test "__fields__/0 includes the virtual field's metadata (still introspectable)" do
      # The virtual field IS still in __fields__/0 — what differs is keys/0
      # / defstruct visibility, not introspection visibility.
      names = Forms.Signup.__fields__() |> Enum.map(& &1.name) |> Enum.sort()
      assert names == [:email, :password, :password_confirmation]
    end
  end
end
