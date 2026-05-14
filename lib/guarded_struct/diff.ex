defmodule GuardedStruct.Diff do
  @moduledoc """
  Field-level diffs between two GuardedStruct instances.

      iex> GuardedStruct.Diff.diff(
      ...>   %User{name: "Alice", age: 30, role: "admin"},
      ...>   %User{name: "Alice", age: 31, role: "user"}
      ...> )
      %{
        age: {:changed, 30, 31},
        role: {:changed, "admin", "user"}
      }

  Equal fields are omitted. Nested struct fields recurse — `name: %User{} → %User{}`
  produces a nested map, not a `:changed` tuple.

  Useful for audit logs, CRM history, and "what changed" UIs.
  """

  @doc """
  Diff two structs of the same module. Returns a map keyed by field name with
  values of one of:

    * `{:changed, old, new}` — primitive value differs
    * `%{...}` — nested struct, recursively diffed (only if there ARE changes)

  Equal fields are omitted from the result.

  Returns `:not_comparable` if the two values are not the same struct module.
  """
  @spec diff(struct() | map() | any(), struct() | map() | any()) :: map() | :not_comparable
  def diff(%mod{} = a, %mod{} = b), do: diff_keys(Map.from_struct(a), Map.from_struct(b))
  def diff(%{} = a, %{} = b) when not is_struct(a) and not is_struct(b), do: diff_keys(a, b)
  def diff(_, _), do: :not_comparable

  defp diff_keys(a, b) do
    keys = Map.keys(a) |> Enum.uniq()

    Enum.reduce(keys, %{}, fn key, acc ->
      av = Map.get(a, key)
      bv = Map.get(b, key)

      case compare(av, bv) do
        :unchanged -> acc
        change -> Map.put(acc, key, change)
      end
    end)
  end

  defp compare(v, v), do: :unchanged

  defp compare(%mod{} = a, %mod{} = b) do
    case diff(a, b) do
      d when d == %{} -> :unchanged
      d -> d
    end
  end

  defp compare(a, b), do: {:changed, a, b}

  @doc """
  Apply a diff to a struct, returning the result of applying the new values.

      iex> User.builder(%{name: "Alice", age: 30}) |> elem(1) |> GuardedStruct.Diff.apply(%{age: {:changed, 30, 31}})
      %User{name: "Alice", age: 31}

  Nested struct diffs apply recursively. `:changed` tuples replace the field
  with their `new` value. Unknown keys in the diff are silently ignored.
  """
  @spec apply(struct() | map(), map()) :: struct() | map()
  def apply(%_{} = struct, diff) when is_map(diff) do
    Enum.reduce(diff, struct, fn
      {key, {:changed, _old, new}}, acc when is_struct(acc) ->
        if Map.has_key?(acc, key), do: Map.put(acc, key, new), else: acc

      {key, %{} = nested}, acc when is_struct(acc) ->
        case Map.get(acc, key) do
          %_{} = current -> Map.put(acc, key, __MODULE__.apply(current, nested))
          _ -> acc
        end

      _, acc ->
        acc
    end)
  end

  def apply(map, diff) when is_map(map) and is_map(diff) do
    Enum.reduce(diff, map, fn
      {key, {:changed, _, new}}, acc ->
        Map.put(acc, key, new)

      {key, %{} = nested}, acc ->
        case Map.get(acc, key) do
          %{} = sub -> Map.put(acc, key, __MODULE__.apply(sub, nested))
          _ -> acc
        end

      _, acc ->
        acc
    end)
  end

  @doc """
  Returns `true` if the two structs are equal field-by-field (same as
  `diff(a, b) == %{}` but skips work for unchanged fields).
  """
  @spec equal?(any(), any()) :: boolean()
  def equal?(a, b) do
    case diff(a, b) do
      :not_comparable -> false
      %{} = d -> map_size(d) == 0
    end
  end
end
