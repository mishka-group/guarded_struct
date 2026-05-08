defmodule GuardedStruct.Schema do
  @moduledoc """
  Emit a JSON Schema or TypeScript declaration for a `GuardedStruct` module.

  ## JSON Schema

      iex> GuardedStruct.Schema.json_schema(MyStruct)
      %{
        "$schema" => "https://json-schema.org/draft/2020-12/schema",
        "type" => "object",
        "properties" => %{...},
        "required" => [...]
      }

  ## TypeScript

      iex> GuardedStruct.Schema.typescript(MyStruct)
      "export interface MyStruct {\\n  name: string;\\n  age?: number;\\n}\\n"
  """

  @json_schema_id "https://json-schema.org/draft/2020-12/schema"

  @doc "Render a `GuardedStruct` module as a JSON-Schema map."
  @spec json_schema(module()) :: map()
  def json_schema(module) do
    fields = module.__fields__()
    keys = module.keys()
    enforce = module.enforce_keys()

    properties =
      keys
      |> Enum.map(fn name -> {to_string(name), field_schema(find_meta(fields, name), module)} end)
      |> Map.new()

    %{
      "$schema" => @json_schema_id,
      "title" => inspect(module),
      "type" => "object",
      "properties" => properties,
      "required" => Enum.map(enforce, &to_string/1)
    }
  end

  @doc "Render as a TypeScript `interface` declaration."
  @spec typescript(module()) :: String.t()
  def typescript(module) do
    fields = module.__fields__()
    keys = module.keys()
    enforce_set = MapSet.new(module.enforce_keys())
    name = module |> inspect() |> String.replace(".", "")

    body =
      keys
      |> Enum.map(fn k ->
        meta = find_meta(fields, k)
        ts_type = ts_type_for(meta)
        opt = if MapSet.member?(enforce_set, k), do: "", else: "?"
        "  #{k}#{opt}: #{ts_type};"
      end)
      |> Enum.join("\n")

    "export interface #{name} {\n#{body}\n}\n"
  end

  defp find_meta(fields, name) do
    Enum.find(fields, &(&1[:name] == name))
  end

  defp field_schema(nil, _module), do: %{}

  defp field_schema(meta, module) do
    case meta[:kind] do
      :sub_field ->
        sub_module = nested_module(module, meta)

        if Code.ensure_loaded?(sub_module) and function_exported?(sub_module, :__fields__, 0) do
          if meta[:list?] do
            %{"type" => "array", "items" => json_schema(sub_module)}
          else
            json_schema(sub_module)
          end
        else
          %{"type" => "object"}
        end

      _ ->
        ops = meta[:__derive_ops__] || %{}
        validate_ops = Map.get(ops, :validate, [])

        base_type(validate_ops)
        |> add_constraints(validate_ops)
        |> maybe_add_default(meta[:default])
    end
  end

  defp nested_module(module, %{name: name}) do
    Module.concat(module, name |> Atom.to_string() |> Macro.camelize())
  end

  defp base_type(ops) do
    cond do
      :string in ops or :not_empty_string in ops -> %{"type" => "string"}
      :integer in ops -> %{"type" => "integer"}
      :float in ops -> %{"type" => "number"}
      :number in ops -> %{"type" => "number"}
      :boolean in ops -> %{"type" => "boolean"}
      :map in ops -> %{"type" => "object"}
      :list in ops -> %{"type" => "array"}
      :atom in ops -> %{"type" => "string"}
      true -> %{}
    end
  end

  defp add_constraints(schema, ops) do
    Enum.reduce(ops, schema, fn op, acc ->
      acc |> Map.merge(op_to_constraint(op, schema))
    end)
  end

  defp op_to_constraint({:max_len, n}, %{"type" => "string"}), do: %{"maxLength" => n}
  defp op_to_constraint({:max_len, n}, %{"type" => "array"}), do: %{"maxItems" => n}
  defp op_to_constraint({:max_len, n}, _), do: %{"maximum" => n}

  defp op_to_constraint({:min_len, n}, %{"type" => "string"}), do: %{"minLength" => n}
  defp op_to_constraint({:min_len, n}, %{"type" => "array"}), do: %{"minItems" => n}
  defp op_to_constraint({:min_len, n}, _), do: %{"minimum" => n}

  defp op_to_constraint(:url, _), do: %{"format" => "uri"}
  defp op_to_constraint(:uuid, _), do: %{"format" => "uuid"}
  defp op_to_constraint(:email_r, _), do: %{"format" => "email"}
  defp op_to_constraint(:email, _), do: %{"format" => "email"}
  defp op_to_constraint(:date, _), do: %{"format" => "date"}
  defp op_to_constraint(:datetime, _), do: %{"format" => "date-time"}
  defp op_to_constraint(:ipv4, _), do: %{"format" => "ipv4"}
  defp op_to_constraint({:regex, pattern}, _), do: %{"pattern" => to_string(pattern)}
  defp op_to_constraint({:enum, list}, _) when is_list(list), do: %{"enum" => list}
  defp op_to_constraint({:enum, "String[" <> rest}, _), do: %{"enum" => parse_enum(rest)}

  defp op_to_constraint({:enum, "Integer[" <> rest}, _) do
    %{"enum" => Enum.map(parse_enum(rest), &String.to_integer/1)}
  end

  defp op_to_constraint(_, _), do: %{}

  defp maybe_add_default(schema, nil), do: schema
  defp maybe_add_default(schema, default), do: Map.put(schema, "default", default)

  defp parse_enum(s) do
    s
    |> String.split("]", parts: 2)
    |> List.first()
    |> String.split("::", trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp ts_type_for(nil), do: "any"

  defp ts_type_for(meta) do
    if meta[:kind] == :sub_field do
      "object"
    else
      ops = meta[:__derive_ops__] || %{}
      validate_ops = Map.get(ops, :validate, [])

      cond do
        :string in validate_ops or :not_empty_string in validate_ops -> "string"
        :integer in validate_ops -> "number"
        :float in validate_ops or :number in validate_ops -> "number"
        :boolean in validate_ops -> "boolean"
        :map in validate_ops -> "Record<string, any>"
        :list in validate_ops -> "any[]"
        :atom in validate_ops -> "string"
        true -> ts_type_for_enum(validate_ops) || "any"
      end
    end
  end

  defp ts_type_for_enum(ops) do
    Enum.find_value(ops, fn
      {:enum, list} when is_list(list) -> Enum.map_join(list, " | ", &"\"#{&1}\"")
      {:enum, "String[" <> rest} -> parse_enum(rest) |> Enum.map_join(" | ", &"\"#{&1}\"")
      _ -> nil
    end)
  end
end
