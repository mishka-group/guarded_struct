defmodule GuardedStruct.Transformers.VerifyCoreKeyPaths do
  @moduledoc false

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer
  alias GuardedStruct.Dsl.{Field, SubField, ConditionalField, VirtualField}

  @impl true
  def after?(GuardedStruct.Transformers.ParseCoreKeys), do: true
  def after?(_), do: false

  @impl true
  def before?(GuardedStruct.Transformers.GenerateBuilder), do: true
  def before?(GuardedStruct.Transformers.GenerateSubFieldModules), do: true
  def before?(_), do: false

  @impl true
  def transform(dsl_state) do
    if strict_mode?() do
      verify!(dsl_state)
    end

    {:ok, dsl_state}
  end

  @doc false
  def verify!(dsl_state) do
    module = Transformer.get_persisted(dsl_state, :module)
    top_level = Transformer.get_entities(dsl_state, [:guardedstruct])
    verify_each(top_level, top_level, module)
    {:ok, dsl_state}
  end

  defp strict_mode? do
    Application.get_env(:guarded_struct, :strict_core_key_paths, false) == true
  end

  defp verify_each(entities, top_level, module) do
    Enum.each(entities, &verify(&1, entities, top_level, module))
  end

  defp verify(%Field{name: name} = f, siblings, top_level, module) do
    check_path(name, f.__from_path__, :from, siblings, top_level, module)
    check_path(name, f.__on_path__, :on, siblings, top_level, module)
  end

  defp verify(%VirtualField{name: name} = vf, siblings, top_level, module) do
    check_path(name, vf.__from_path__, :from, siblings, top_level, module)
    check_path(name, vf.__on_path__, :on, siblings, top_level, module)
  end

  defp verify(%SubField{name: name} = sf, siblings, top_level, module) do
    check_path(name, sf.__from_path__, :from, siblings, top_level, module)
    check_path(name, sf.__on_path__, :on, siblings, top_level, module)

    children = sf.fields ++ sf.sub_fields ++ sf.conditional_fields
    verify_each(children, top_level, module)
  end

  defp verify(%ConditionalField{name: name} = cf, siblings, top_level, module) do
    check_path(name, cf.__from_path__, :from, siblings, top_level, module)
    check_path(name, cf.__on_path__, :on, siblings, top_level, module)

    children = cf.fields ++ cf.sub_fields ++ cf.conditional_fields
    verify_each(children, top_level, module)
  end

  defp verify(_, _, _, _), do: :ok

  defp check_path(_field, nil, _kind, _siblings, _top_level, _module), do: :ok

  defp check_path(field, [:root | rest], kind, _siblings, top_level, module) do
    case resolve(rest, top_level) do
      :ok ->
        :ok

      {:error, missing} ->
        raise_missing(field, kind, [:root | rest], missing, module)
    end
  end

  defp check_path(field, path, kind, siblings, _top_level, module) do
    case resolve(path, siblings) do
      :ok ->
        :ok

      {:error, missing} ->
        raise_missing(field, kind, path, missing, module)
    end
  end

  defp resolve([], _entities), do: :ok

  defp resolve([name | rest], entities) do
    case Enum.find(entities, &name_matches?(&1, name)) do
      nil ->
        {:error, name}

      %SubField{} = sub ->
        resolve(rest, sub.fields ++ sub.sub_fields ++ sub.conditional_fields)

      %ConditionalField{} = cond ->
        # Conditional children share the parent's name. To traverse THROUGH a
        # conditional, accept if ANY variant has the rest of the path.
        children = cond.fields ++ cond.sub_fields ++ cond.conditional_fields

        if rest == [] or Enum.any?(children, &has_path?(&1, rest)) do
          :ok
        else
          {:error, List.first(rest)}
        end

      _leaf ->
        if rest == [], do: :ok, else: {:error, List.first(rest)}
    end
  end

  defp has_path?(%SubField{} = sub, path) do
    case resolve(path, sub.fields ++ sub.sub_fields ++ sub.conditional_fields) do
      :ok -> true
      _ -> false
    end
  end

  defp has_path?(_entity, []), do: true
  defp has_path?(_, _), do: false

  defp name_matches?(%{name: name}, target), do: name == target
  defp name_matches?(_, _), do: false

  defp raise_missing(field, kind, path, missing, module) do
    rendered = path |> Enum.map(&to_string/1) |> Enum.join("::")

    raise Spark.Error.DslError,
      message:
        "`#{kind}: #{inspect(rendered)}` on field #{inspect(field)} references " <>
          "`#{inspect(missing)}`, which is not a declared field.\n" <>
          "Check the path against your schema's field/sub_field/conditional_field declarations.",
      path: [:guardedstruct, :field, field, kind],
      module: module
  end
end
