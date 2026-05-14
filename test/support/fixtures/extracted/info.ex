defmodule GuardedStructTest.Fixtures.Info.EverythingUser.Hashers do
  @moduledoc false
  def hash(field, v) when is_binary(v), do: {:ok, field, v}
  def hash(field, _), do: {:error, field, "not a string"}
end

defmodule GuardedStructTest.Fixtures.Info.EverythingUser.Ids do
  @moduledoc false
  def gen, do: "id-stub"
end

defmodule GuardedStructTest.Fixtures.Info.EverythingUser do
  use GuardedStruct

  alias GuardedStructTest.Fixtures.Info.EverythingUser.{Hashers, Ids}

  guardedstruct enforce: true, authorized_fields: true, json: true do
    field :id, String.t(), auto: {Ids, :gen}
    field :password, String.t(), validator: {Hashers, :hash}
    field :nickname, String.t(), enforce: false, derives: "validate(string, max_len=20)"
    field :status, String.t(), default: "active"
    virtual_field :password_confirm, String.t()
    dynamic_field :metadata

    sub_field :address, struct() do
      field :city, String.t(), enforce: true
      field :zip, String.t()
    end

    conditional_field :billing, any() do
      field :billing, String.t(), hint: "preset_name", derives: "validate(string)"

      sub_field :billing, struct() do
        field :method, String.t(), enforce: true
        field :account, String.t()
      end
    end
  end
end

defmodule GuardedStructTest.Fixtures.Info.HeadersMap do
  use GuardedStruct

  guardedstruct do
    field ~r/^X-[A-Z][A-Za-z\-]*$/, String.t(), derives: "validate(string)"
  end
end
