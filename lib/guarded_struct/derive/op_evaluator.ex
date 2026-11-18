defmodule GuardedStruct.Derive.OpEvaluator do
  @moduledoc false

  @spec preevaluate(nil | map()) :: nil | map()
  def preevaluate(nil), do: nil

  def preevaluate(ops) when is_map(ops) do
    Map.new(ops, fn {key, op_list} -> {key, Enum.map(op_list, &rewrite/1)} end)
  end

  @spec rewrite_tuple(tuple()) :: tuple() | map()
  def rewrite_tuple(op_tuple), do: rewrite(op_tuple)

  defp rewrite({:enum, "String[" <> rest}) do
    {:enum, split_to_list(strip_close(rest))}
  end

  # sobelow_skip ["DOS.StringToAtom", "DOS.ModuleConcat"]
  defp rewrite({:enum, "Atom[" <> rest}) do
    items = rest |> strip_close() |> split_to_list() |> Enum.map(&operand_atom/1)
    {:enum, items}
  end

  defp rewrite({:enum, "Integer[" <> rest}) do
    case parse_all(rest, &Integer.parse/1) do
      {:ok, items} -> {:enum, items}
      :error -> {:enum, "Integer[" <> rest}
    end
  end

  defp rewrite({:enum, "Float[" <> rest}) do
    case parse_all(rest, &Float.parse/1) do
      {:ok, items} -> {:enum, items}
      :error -> {:enum, "Float[" <> rest}
    end
  end

  defp rewrite({:enum, "Map[" <> rest}) do
    items = rest |> strip_close() |> split_to_list() |> Enum.map(&safe_eval/1)

    if Enum.any?(items, &is_nil/1) do
      {:enum, "Map[" <> rest}
    else
      {:enum, items}
    end
  end

  defp rewrite({:enum, "Tuple[" <> rest}) do
    items = rest |> strip_close() |> split_to_list() |> Enum.map(&safe_eval/1)

    if Enum.any?(items, &is_nil/1) do
      {:enum, "Tuple[" <> rest}
    else
      {:enum, items}
    end
  end

  defp rewrite({:equal, "String::" <> value}), do: {:equal, value}

  defp rewrite({:equal, "Integer::" <> value}) do
    case Integer.parse(value) do
      {n, ""} -> {:equal, n}
      _ -> {:equal, "Integer::" <> value}
    end
  end

  defp rewrite({:equal, "Float::" <> value}) do
    case Float.parse(value) do
      {f, ""} -> {:equal, f}
      _ -> {:equal, "Float::" <> value}
    end
  end

  defp rewrite({:equal, "Atom::" <> value}) do
    {:equal, operand_atom(value)}
  end

  defp rewrite({:equal, "Map::" <> value}) do
    case safe_eval(value) do
      nil -> {:equal, "Map::" <> value}
      term -> {:equal, term}
    end
  end

  defp rewrite({:equal, "Tuple::" <> value}) do
    case safe_eval(value) do
      nil -> {:equal, "Tuple::" <> value}
      term -> {:equal, term}
    end
  end

  defp rewrite({:record, tag}) when is_binary(tag), do: {:record, operand_atom(tag)}

  defp rewrite({:custom, {mods, fun}}) when is_list(mods) and is_atom(fun),
    do: {:custom, {operand_module(mods), fun}}

  defp rewrite({:custom, value}) when is_binary(value) do
    parts =
      value
      |> String.replace(["[", "]"], "")
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    case parts do
      [module_str, fun_str] ->
        {:custom, {operand_module([module_str]), operand_atom(fun_str)}}

      _ ->
        {:custom, value}
    end
  end

  defp rewrite(other), do: other

  defp parse_all(rest, parse) do
    parsed = rest |> strip_close() |> split_to_list() |> Enum.map(parse)

    if Enum.all?(parsed, &match?({_, ""}, &1)),
      do: {:ok, Enum.map(parsed, &elem(&1, 0))},
      else: :error
  end

  defp strip_close(s) do
    case String.split(s, "]", parts: 2) do
      [body, _rest] -> body
      [body] -> body
    end
  end

  defp split_to_list(s) do
    s |> String.split("::", trim: true) |> Enum.map(&String.trim/1)
  end

  # Operands come from the developer's derive strings, never from user input.
  # sobelow_skip ["DOS.StringToAtom"]
  defp operand_atom(string), do: String.to_atom(string)

  # Operands come from the developer's derive strings, never from user input.
  # sobelow_skip ["DOS.ModuleConcat"]
  defp operand_module(parts), do: Module.concat(parts)

  # Operands come from the developer's derive strings, never from user input.
  # sobelow_skip ["RCE.CodeModule"]
  defp safe_eval(value) do
    case Code.eval_string(value) do
      {term, _} -> term
    end
  rescue
    _ -> nil
  end
end
