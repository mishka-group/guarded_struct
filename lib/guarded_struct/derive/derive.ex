defmodule GuardedStruct.Derive do
  @moduledoc false

  alias GuardedStruct.Derive.{Parser, SanitizerDerive, ValidationDerive}

  @type derive_input :: %{
          required(:field) => atom(),
          optional(:derive) => String.t() | nil,
          optional(:derive_ops) => map() | nil,
          optional(:hint) => any()
        }

  @doc """
  Apply derive ops to each named field in `data`. Returns `{:ok, data'}` with
  sanitised/validated values merged back, or `{:error, errors}` with a flat
  list of `%{field, action, message}` maps.
  """
  @spec derive({:ok, map(), [derive_input]}) :: {:ok, map()} | {:error, [map()]}
  def derive({:ok, data, derive_inputs}) do
    reduced =
      Enum.reduce(derive_inputs, %{}, fn input, acc ->
        ops =
          case Map.get(input, :derive_ops, :__missing__) do
            :__missing__ -> Parser.parser(input.derive)
            v -> v
          end

        field_value = Map.get(data, input.field)
        hint = Map.get(input, :hint) || []

        update(field_value, ops, hint, input, acc)
      end)

    case collect_errors(reduced) do
      [] -> {:ok, Map.merge(data, reduced)}
      errors -> {:error, errors}
    end
  end

  defp update(nil, _ops, _hint, _input, acc), do: acc

  defp update(field_value, ops, hints, input, acc)
       when is_list(ops) and ops != [] do
    list_data? = is_list(field_value) and length(field_value) == length(ops)

    values =
      if list_data?,
        do: field_value,
        else: List.duplicate(field_value, length(ops))

    results =
      [ops, values, hints]
      |> Enum.zip()
      |> Enum.map(fn {op, value, hint} ->
        op = if op == [], do: nil, else: op
        run_one(op, input.field, value, hint)
      end)

    {errors, ok_values} =
      Enum.split_with(results, &match?({:error, _}, &1))

    flat_errors = Enum.flat_map(errors, fn {:error, e} -> e end)

    value_to_store =
      cond do
        list_data? and flat_errors != [] -> {:error, flat_errors}
        list_data? -> ok_values
        ok_values != [] -> List.first(ok_values)
        true -> {:error, flat_errors}
      end

    Map.put(acc, input.field, value_to_store)
  end

  defp update(field_value, ops, hint, input, acc) do
    ops = if ops == [], do: nil, else: ops
    Map.put(acc, input.field, run_one(ops, input.field, field_value, hint))
  end

  defp run_one(ops, field, value, hint) do
    {processed, errors} =
      {field, value}
      |> SanitizerDerive.call(get_in_ops(ops, :sanitize))
      |> ValidationDerive.call(get_in_ops(ops, :validate), hint)

    if errors == [], do: processed, else: {:error, errors}
  end

  defp get_in_ops(nil, _key), do: nil
  defp get_in_ops(map, key) when is_map(map), do: Map.get(map, key)
  defp get_in_ops(_, _), do: nil

  defp collect_errors(reduced) do
    reduced
    |> Map.values()
    |> Enum.filter(&match?({:error, _}, &1))
    |> Enum.flat_map(fn {:error, e} -> e end)
  end
end
