defmodule GuardedStruct.Derive.OpParamValidator do
  @moduledoc false

  # Spark.Error.DslError on bad param shapes for parameterised derive ops.
  # Examples of the kind of typo this catches at compile time:
  #
  #   validate(max_len=foo)   — max_len needs an integer, got "foo"
  #   validate(min_len=-2)    — min_len needs a non-negative integer
  #   validate(record=42)     — record tag must be an atom-shaped string
  #
  # Bare atoms (e.g. :string, :not_empty) are not param-typed and pass.

  @doc """
  Validate the parameter types of an op-map (`%{validate: [...], sanitize: [...]}`).
  Raises Spark.Error.DslError if anything's off; returns the input unchanged on success.
  """
  @spec validate!(map() | nil, atom(), module()) :: map() | nil
  def validate!(nil, _field_name, _module), do: nil

  def validate!(%{} = ops, field_name, module) do
    ops
    |> Map.get(:validate, [])
    |> Enum.each(&check_validate(&1, field_name, module))

    ops
    |> Map.get(:sanitize, [])
    |> Enum.each(&check_sanitize(&1, field_name, module))

    ops
  end

  defp check_validate({:max_len, n}, _f, _m) when is_integer(n) and n >= 0, do: :ok

  defp check_validate({:max_len, other}, field_name, module),
    do: bad_param!(:max_len, "non-negative integer", other, field_name, module)

  defp check_validate({:min_len, n}, _f, _m) when is_integer(n) and n >= 0, do: :ok

  defp check_validate({:min_len, other}, field_name, module),
    do: bad_param!(:min_len, "non-negative integer", other, field_name, module)

  defp check_validate({:tell, n}, _f, _m) when is_integer(n), do: :ok

  defp check_validate({:tell, other}, field_name, module),
    do: bad_param!(:tell, "integer (country code)", other, field_name, module)

  defp check_validate({:regex, value}, _f, _m)
       when is_list(value) or is_binary(value),
       do: :ok

  defp check_validate({:regex, other}, field_name, module),
    do: bad_param!(:regex, "charlist or string", other, field_name, module)

  defp check_validate({:enum, list}, _f, _m) when is_list(list), do: :ok
  defp check_validate({:enum, "String[" <> _}, _f, _m), do: :ok
  defp check_validate({:enum, "Atom[" <> _}, _f, _m), do: :ok
  defp check_validate({:enum, "Integer[" <> _}, _f, _m), do: :ok
  defp check_validate({:enum, "Float[" <> _}, _f, _m), do: :ok
  defp check_validate({:enum, "Map[" <> _}, _f, _m), do: :ok
  defp check_validate({:enum, "Tuple[" <> _}, _f, _m), do: :ok

  defp check_validate({:enum, other}, field_name, module),
    do:
      bad_param!(
        :enum,
        "Type[…] form (String/Atom/Integer/Float/Map/Tuple)",
        other,
        field_name,
        module
      )

  defp check_validate({:equal, value}, _f, _m) when not is_binary(value), do: :ok
  defp check_validate({:equal, "String::" <> _}, _f, _m), do: :ok
  defp check_validate({:equal, "Integer::" <> _}, _f, _m), do: :ok
  defp check_validate({:equal, "Float::" <> _}, _f, _m), do: :ok
  defp check_validate({:equal, "Atom::" <> _}, _f, _m), do: :ok
  defp check_validate({:equal, "Map::" <> _}, _f, _m), do: :ok
  defp check_validate({:equal, "Tuple::" <> _}, _f, _m), do: :ok

  defp check_validate({:equal, other}, field_name, module),
    do:
      bad_param!(
        :equal,
        "Type::value form (String/Integer/Float/Atom/Map/Tuple)",
        other,
        field_name,
        module
      )

  defp check_validate({:record, tag}, _f, _m) when is_atom(tag), do: :ok
  defp check_validate({:record, tag}, _f, _m) when is_binary(tag), do: :ok

  defp check_validate({:record, other}, field_name, module),
    do: bad_param!(:record, "atom or string tag", other, field_name, module)

  defp check_validate({:custom, {mods, fun}}, _f, _m)
       when is_list(mods) and is_atom(fun),
       do: :ok

  defp check_validate({:custom, value}, _f, _m) when is_binary(value), do: :ok

  defp check_validate({:custom, other}, field_name, module),
    do: bad_param!(:custom, "[Module.Path, :function_name] or string", other, field_name, module)

  defp check_validate(%{either: list}, field_name, module) when is_list(list) do
    Enum.each(list, &check_validate(&1, field_name, module))
  end

  defp check_validate(_other, _f, _m), do: :ok

  defp check_sanitize({:tag, sub_op}, _f, _m) when is_atom(sub_op) or is_binary(sub_op),
    do: :ok

  defp check_sanitize({:tag, other}, field_name, module),
    do: bad_param!(:tag, "atom (e.g. :strip_tags) or string", other, field_name, module)

  defp check_sanitize(_other, _f, _m), do: :ok

  defp bad_param!(op, expected, actual, field_name, module) do
    raise Spark.Error.DslError,
      message:
        "invalid parameter for `#{op}` on field #{inspect(field_name)}: " <>
          "expected #{expected}, got #{inspect(actual)}.",
      path: [:guardedstruct, :field, field_name, :derive],
      module: module
  end
end
