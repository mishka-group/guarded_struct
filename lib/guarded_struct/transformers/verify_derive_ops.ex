defmodule GuardedStruct.Transformers.VerifyDeriveOps do
  @moduledoc false

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer
  alias GuardedStruct.Dsl.{Field, SubField, ConditionalField, VirtualField}
  alias GuardedStruct.Derive.Registry

  @impl true
  def after?(GuardedStruct.Transformers.ParseDerive), do: true
  def after?(_), do: false

  @impl true
  def before?(GuardedStruct.Transformers.GenerateBuilder), do: true
  def before?(GuardedStruct.Transformers.GenerateSubFieldModules), do: true
  def before?(_), do: false

  @impl true
  def transform(dsl_state) do
    cond do
      not strict_mode?() ->
        {:ok, dsl_state}

      user_extensions_configured?() ->
        {:ok, dsl_state}

      true ->
        module = Transformer.get_persisted(dsl_state, :module)
        entities = Transformer.get_entities(dsl_state, [:guardedstruct])
        Enum.each(entities, &verify_entity(&1, module))
        {:ok, dsl_state}
    end
  end

  defp verify_entity(%Field{name: name, __derive_ops__: ops}, module) do
    check_ops(ops, name, module)
  end

  defp verify_entity(%VirtualField{name: name, __derive_ops__: ops}, module) do
    check_ops(ops, name, module)
  end

  defp verify_entity(%SubField{name: name, __derive_ops__: ops} = sf, module) do
    check_ops(ops, name, module)
    Enum.each(sf.fields, &verify_entity(&1, module))
    Enum.each(sf.sub_fields, &verify_entity(&1, module))
    Enum.each(sf.conditional_fields, &verify_entity(&1, module))
  end

  defp verify_entity(%ConditionalField{name: name, __derive_ops__: ops} = cf, module) do
    check_ops(ops, name, module)
    Enum.each(cf.fields, &verify_entity(&1, module))
    Enum.each(cf.sub_fields, &verify_entity(&1, module))
    Enum.each(cf.conditional_fields, &verify_entity(&1, module))
  end

  defp verify_entity(_, _), do: :ok

  defp check_ops(nil, _field, _module), do: :ok
  defp check_ops(%{} = ops, _field, _module) when map_size(ops) == 0, do: :ok

  defp check_ops(%{} = ops, field, module) do
    bad_validate =
      ops |> Map.get(:validate, []) |> Enum.flat_map(&extract_unknown(&1, :validate))

    bad_sanitize =
      ops |> Map.get(:sanitize, []) |> Enum.flat_map(&extract_unknown(&1, :sanitize))

    case bad_validate ++ bad_sanitize do
      [] ->
        :ok

      [{kind, _} | _] = unknowns ->
        names = Enum.map(unknowns, fn {k, n} -> "#{k}=#{inspect(n)}" end) |> Enum.join(", ")
        suggestions = Enum.map(unknowns, &suggest/1) |> Enum.reject(&is_nil/1)

        suggestion_block =
          case suggestions do
            [] -> ""
            [s] -> "\nDid you mean #{s}?"
            _ -> "\nDid you mean:\n  - " <> Enum.join(suggestions, "\n  - ")
          end

        raise Spark.Error.DslError,
          message:
            "unknown derive op(s) on field #{inspect(field)}: #{names}." <>
              suggestion_block <>
              "\nBuilt-in #{kind} ops are listed in `GuardedStruct.Derive.Registry`.",
          path: [:guardedstruct, :field, field, :derive],
          module: module
    end
  end

  @suggestion_threshold 0.7
  @suggestion_count 3

  defp suggest({kind, name}) when is_atom(name) do
    candidates =
      case kind do
        :validate -> Registry.validate_ops()
        :sanitize -> Registry.sanitize_ops()
      end

    name_str = Atom.to_string(name)

    matches =
      candidates
      |> Enum.map(fn op -> {op, String.jaro_distance(name_str, Atom.to_string(op))} end)
      |> Enum.filter(fn {_op, d} -> d >= @suggestion_threshold end)
      |> Enum.sort_by(fn {_op, d} -> d end, :desc)
      |> Enum.take(@suggestion_count)
      |> Enum.map(fn {op, _} -> "`:#{op}`" end)

    case matches do
      [] -> nil
      [single] -> single
      list -> "one of " <> Enum.join(list, ", ")
    end
  end

  defp suggest(_), do: nil

  defp extract_unknown(name, kind) when is_atom(name) do
    if known?(name, kind), do: [], else: [{kind, name}]
  end

  defp extract_unknown({name, _arg}, kind) when is_atom(name) do
    if known?(name, kind), do: [], else: [{kind, name}]
  end

  defp extract_unknown(%{either: inner}, _kind) when is_list(inner) do
    Enum.flat_map(inner, &extract_unknown(&1, :validate))
  end

  defp extract_unknown(_, _), do: []

  defp known?(name, :validate) do
    Registry.known_validate?(name) or
      MapSet.member?(GuardedStruct.Derive.Extension.all_extension_validators(), name)
  end

  defp known?(name, :sanitize) do
    Registry.known_sanitize?(name) or
      MapSet.member?(GuardedStruct.Derive.Extension.all_extension_sanitizers(), name)
  end

  defp strict_mode? do
    Application.get_env(:guarded_struct, :strict_derive_ops, false) == true
  end

  defp user_extensions_configured? do
    Application.get_env(:guarded_struct, :validate_derive) != nil or
      Application.get_env(:guarded_struct, :sanitize_derive) != nil
  end
end
