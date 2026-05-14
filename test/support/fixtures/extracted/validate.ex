defmodule GuardedStructTest.Fixtures.Validate.Person do
  use GuardedStruct

  guardedstruct do
    field :name, String.t(),
      enforce: true,
      derives: "sanitize(trim) validate(string, max_len=80)"

    field :age, integer(), derives: "validate(integer, min_len=0, max_len=120)"
    field :email, String.t(), derives: "validate(email_r)"
    field :role, String.t(), derives: "validate(enum=String[admin::user::guest])"
    field :account_type, String.t(), derives: "validate(enum=String[personal::business])"

    field :parent_email, String.t(),
      derives: "validate(email_r)",
      on: "root::account_type"

    field :nickname, String.t(), validator: {__MODULE__, :nickname_validator}
  end

  def nickname_validator(:nickname, value) do
    if is_binary(value) and byte_size(value) >= 3,
      do: {:ok, :nickname, value},
      else: {:error, :nickname, "nickname too short"}
  end

  def nickname_validator(name, value), do: {:ok, name, value}
end

defmodule GuardedStructTest.Fixtures.Validate.WithAuth do
  use GuardedStruct

  guardedstruct do
    field :name, String.t(), derives: "validate(string)"

    sub_field :auth, struct() do
      field :role, String.t(), derives: "validate(enum=String[admin::user])"
    end
  end
end
