defmodule GuardedStruct.Errors do
  @moduledoc """
  Splode error aggregator for GuardedStruct runtime errors.

  `builder/1` returns errors as `{:error, [%{field, action, message, ...}]}`.
  This module wraps that list into Splode exceptions, giving you
  `traverse_errors/2`, `to_class/1`, `set_path/2`, and JSON serialization.

  ## Usage

      case MyStruct.builder(input) do
        {:ok, _} = ok ->
          ok

        {:error, errs} ->
          {:error, GuardedStruct.Errors.from_tuple(errs)}
      end

  Or build a single error directly:

      GuardedStruct.Errors.Validation.exception(
        field: :email,
        action: :email_r,
        message: "Invalid email format"
      )
  """

  use Splode,
    error_classes: [
      invalid: GuardedStruct.Errors.Invalid
    ],
    unknown_error: GuardedStruct.Errors.Unknown

  @doc """
  Convert an error tuple list into a Splode error class. Accepts either the
  inner list or the full `{:error, list}` tuple.
  """
  @spec from_tuple({:error, list()} | list()) :: Splode.Error.t()
  def from_tuple({:error, errors}) when is_list(errors), do: from_tuple(errors)

  def from_tuple(errors) when is_list(errors) do
    errors
    |> Enum.map(&to_splode/1)
    |> to_class()
  end

  defp to_splode(%{field: field, errors: child_errors, action: :conditionals})
       when is_list(child_errors) do
    GuardedStruct.Errors.Validation.exception(
      field: field,
      action: :conditionals,
      message: "Conditional field validation failed",
      child_errors: Enum.map(child_errors, &to_splode/1)
    )
  end

  defp to_splode(%{field: field, action: action} = m) do
    GuardedStruct.Errors.Validation.exception(
      field: field,
      action: action,
      message: Map.get(m, :message),
      hint: Map.get(m, :__hint__),
      vars: Map.drop(m, [:field, :action, :message, :__hint__]) |> Enum.to_list()
    )
  end

  defp to_splode(other) do
    GuardedStruct.Errors.Unknown.exception(error: other, message: inspect(other))
  end
end
