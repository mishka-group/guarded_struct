defmodule GuardedStructTest.Fixtures.VirtualField.Signup do
  use GuardedStruct

  guardedstruct do
    field :email, String.t(), enforce: true, derives: "validate(string, email_r)"
    field :password, String.t(), enforce: true, derives: "validate(string, min_len=8)"
    virtual_field :password_confirm, String.t(), derives: "validate(string)"
  end

  # Convention: `main_validator/1` is auto-discovered by the runtime when
  # defined on the user module (no need for an explicit MFA tuple).
  def main_validator(attrs) do
    if attrs[:password] == attrs[:password_confirm] do
      {:ok, attrs}
    else
      {:error, [%{field: :password_confirm, action: :match, message: "passwords don't match"}]}
    end
  end
end

defmodule GuardedStructTest.Fixtures.VirtualField.WithDynamic do
  use GuardedStruct

  guardedstruct do
    field :name, String.t(), enforce: true, derives: "validate(string)"
    dynamic_field :metadata
  end
end
