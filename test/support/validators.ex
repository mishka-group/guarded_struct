# Shared validator helpers referenced by conditional-field fixtures.
# Moved here (from `test/test_helper.exs`) so they compile BEFORE the
# fixture files in `test/support/fixtures/extracted/`, which reference
# them via `validator: {ConditionalFieldValidatorTestValidators, :fn}`
# tuples. Without this, the `VerifyValidatorMFA` verifier fires during
# fixture compilation (test_helper.exs hasn't run yet at that point).

defmodule ConditionalFieldValidatorTestValidators do
  @moduledoc false

  def validate_string_data(field, value) when is_binary(value), do: {:ok, field, value}
  def validate_string_data(field, _value), do: {:error, field, "It is not string"}

  def validate_map_data(field, value) when is_map(value), do: {:ok, field, value}
  def validate_map_data(field, _value), do: {:error, field, "It is not map"}

  def validate_list_data(field, value) when is_list(value), do: {:ok, field, value}
  def validate_list_data(field, _value), do: {:error, field, "It is not list"}

  def validate_flat_list_data(field, value) when is_list(value),
    do: {:ok, field, List.flatten(value)}

  def validate_flat_list_data(field, _value), do: {:error, field, "It is not list"}

  def validate_int_data(field, value) when is_integer(value), do: {:ok, field, value}
  def validate_int_data(field, _value), do: {:error, field, "It is not integer"}
end
