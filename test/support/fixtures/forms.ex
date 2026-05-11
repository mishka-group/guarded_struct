defmodule GuardedStructFixtures.Forms do
  @moduledoc """
  Real-world signup / login forms.

  Exercises:
    * `virtual_field` — `password_confirmation` is validated but excluded from `defstruct`
    * Per-field `validator:` — hashes the password on accept (transforms the value)
    * `main_validator/1` auto-discovery — cross-field check that password == confirmation
    * `jason: true` — `Signup` is JSON-encodable
  """

  defmodule Hasher do
    @moduledoc false

    # Length-checks the plaintext BEFORE hashing — otherwise the per-field
    # derive (which runs *after* the validator) would only see the hash and
    # the length rule would always pass.
    def hash(field, value)
        when is_binary(value) and byte_size(value) >= 8 and byte_size(value) <= 128 do
      {:ok, field, :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)}
    end

    def hash(field, value) when is_binary(value),
      do: {:error, field, "password must be 8-128 characters"}

    def hash(field, value),
      do: {:error, field, "expected a string, got #{inspect(value)}"}
  end

  defmodule Signup do
    use GuardedStruct

    guardedstruct jason: true do
      field(:email, String.t(),
        enforce: true,
        derives: "sanitize(trim, downcase) validate(string, email_r, max_len=320)"
      )

      field(:password, String.t(),
        enforce: true,
        derives: "validate(string)",
        validator: {Hasher, :hash}
      )

      virtual_field(:password_confirmation, String.t(),
        enforce: true,
        derives: "validate(string)"
      )
    end

    # main_validator/1 is picked up automatically by the runtime
    def main_validator(%{password: hashed, password_confirmation: plain} = attrs)
        when is_binary(plain) do
      # `password` is already hashed by Hasher.hash/2 above; we hash the plain
      # confirmation the same way and compare.
      {_, _, hashed_confirm} = Hasher.hash(:password_confirmation, plain)
      if hashed == hashed_confirm, do: {:ok, attrs}, else: passwords_mismatch()
    end

    def main_validator(_attrs), do: passwords_mismatch()

    defp passwords_mismatch do
      {:error,
       [%{field: :password_confirmation, action: :match, message: "passwords don't match"}]}
    end
  end

  defmodule Login do
    use GuardedStruct

    guardedstruct do
      field(:email, String.t(),
        enforce: true,
        derives: "sanitize(trim, downcase) validate(string, email_r)"
      )

      field(:password, String.t(),
        enforce: true,
        derives: "validate(string, min_len=1)"
      )
    end
  end
end
