defmodule GuardedStruct.Derive do
  @moduledoc false

  alias GuardedStruct.Derive.{Extension, SanitizerDerive, ValidationDerive}

  @type derive_ops :: nil | map() | [map() | nil | []]

  @type derive_input :: %{
          required(:field) => atom(),
          required(:derive_ops) => derive_ops(),
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
        field_value = Map.get(data, input.field)
        hint = Map.get(input, :hint) || []

        update(field_value, input.derive_ops, hint, input, acc)
      end)

    case collect_errors(reduced) do
      [] -> {:ok, Map.merge(data, reduced)}
      errors -> {:error, errors}
    end
  end

  # A nil value skips every op except `sanitize(default_when_nil=...)`, which
  # replaces it; the whole derive string then runs on that default.
  defp update(nil, ops, hint, input, acc) do
    case nil_default(ops) do
      {:ok, default} -> update(default, ops, hint, input, acc)
      :none -> acc
    end
  end

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

  defp nil_default(ops) do
    ops
    |> List.wrap()
    |> Enum.flat_map(&(&1 |> get_in_ops(:sanitize) |> List.wrap()))
    |> Enum.find_value(:none, fn
      {:default_when_nil, default} when not is_nil(default) -> {:ok, default}
      _other -> nil
    end)
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

  @doc """
  The modules that serve the ops no built-in clause or derive extension handles:
  the `validate_derive` / `sanitize_derive` section option of the module being
  built first, then the application config of the same name.
  """
  @spec fallback_modules(:validate_derive | :sanitize_derive) :: [module()]
  def fallback_modules(option) when option in [:validate_derive, :sanitize_derive] do
    section_modules(Extension.current_module(), option) ++
      List.wrap(Application.get_env(:guarded_struct, option))
  end

  defp section_modules(nil, _option), do: []

  defp section_modules(module, option) do
    module.__guarded_information__()
    |> Map.get(:options, %{})
    |> Map.get(option)
    |> List.wrap()
  end
end
