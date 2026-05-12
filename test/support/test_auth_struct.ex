defmodule GuardedStructTest.Support.TestAuthStruct do
  @moduledoc """
  Shared test fixture used by `validator_derive_test.exs` and `global_test.exs`.

  Lives in `test/support/` (compiled before any test file) to avoid the
  test-file-ordering / cross-test-load issue that surfaces on Elixir 1.17
  / OTP 27 on CI when one test file's inner module is referenced from
  another.
  """

  use GuardedStruct

  guardedstruct do
    field(:action, String.t(), derives: "validate(not_empty)")

    sub_field(:path, struct(), main_validator: {__MODULE__, :main_validator}) do
      field(:role, String.t(), validator: {__MODULE__, :validator})
      field(:custom_path, String.t(), derives: "validate(not_empty)")

      sub_field(:rel, struct()) do
        field(:social, String.t(), derives: "validate(not_empty)")
      end
    end

    field(:changed, String.t(),
      derives: "validate(not_empty)",
      validator: {__MODULE__, :test_validator}
    )
  end

  def test_validator(:changed, value) do
    if is_binary(value),
      do: {:ok, :changed, value <> "::Changed"},
      else: {:error, :changed, "No, never"}
  end

  def validator(:role, value) do
    if is_binary(value), do: {:ok, :role, value}, else: {:error, :role, "No, never"}
  end

  def validator(field, value) do
    {:ok, field, value}
  end

  def main_validator(value) do
    if Map.get(value, :changed) == 555_555 or Map.get(value, :action) == 25 do
      {:error, %{message: "there is an Error", field: :global, action: :main_validator}}
    else
      {:ok, value}
    end
  end
end
