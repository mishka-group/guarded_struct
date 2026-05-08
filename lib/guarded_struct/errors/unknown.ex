defmodule GuardedStruct.Errors.Unknown do
  @moduledoc false

  use Splode.Error, fields: [:error, :message], class: :invalid

  @impl true
  def message(%{message: msg}) when is_binary(msg), do: msg
  def message(%{error: e}), do: inspect(e)
end
