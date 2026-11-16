defmodule GuardedStructTest.NotNilValueTest do
  use ExUnit.Case, async: true

  defmodule Payment do
    use GuardedStruct

    guardedstruct do
      field :amount, integer(), enforce: true, derives: "validate(not_nil_value, integer)"
      field :note, String.t(), derives: "validate(string)"

      field :currency, String.t(),
        derives: ~s|sanitize(default_when_nil="USD") validate(not_nil_value, string)|

      field :token, String.t(),
        enforce: true,
        derives: "validate(not_nil_value, string)",
        validator: {__MODULE__, :token}
    end

    def token(:token, "ok"), do: {:ok, :token, "ok"}
    def token(:token, _other), do: {:error, :token, "The token field must be ok"}
  end

  test "not_nil_value refuses a field given as nil" do
    assert {:error, [%{field: :amount, action: :not_nil_value}]} =
             Payment.builder(%{amount: nil, token: "ok"})
  end

  test "a field its validator refused reports that error only, not not_nil_value as well" do
    assert {:error, [%{field: :token, action: :validator}]} =
             Payment.builder(%{amount: 1, token: "bad"})
  end

  test "every other op still skips a nil field" do
    assert {:ok, %Payment{note: nil}} = Payment.builder(%{amount: 1, note: nil, token: "ok"})
  end

  test "default_when_nil still replaces nil before not_nil_value runs" do
    assert {:ok, %Payment{currency: "USD"}} =
             Payment.builder(%{amount: 1, currency: nil, token: "ok"})
  end

  test "a value is checked by the rest of the string as before" do
    assert {:error, [%{field: :amount, action: :integer}]} =
             Payment.builder(%{amount: "1", token: "ok"})
  end
end
