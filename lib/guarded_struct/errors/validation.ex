defmodule GuardedStruct.Errors.Validation do
  @moduledoc "Single field-level validation error."

  use Splode.Error,
    fields: [:field, :action, :message, :hint, :child_errors],
    class: :invalid

  @impl true
  def message(%{message: m}) when is_binary(m), do: m
  def message(%{field: f, action: a}), do: "validation failed on #{inspect(f)} (#{inspect(a)})"
end
