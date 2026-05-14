defmodule GuardedStruct.Verifiers.VerifyAtomic do
  @moduledoc """
  Compile-time verifier that rejects `atomic: true` resources whose
  derive ops can't translate to atomic SQL.

  Runs only when the section's `atomic` option is `true`. Walks every
  field/sub_field/conditional_field/virtual_field, classifies each op
  via `GuardedStruct.AtomicClassifier`, and aggregates blockers. If any
  found, raises `Spark.Error.DslError` with one bullet per blocker.

  ## Structure

  One pattern-match clause per entity type — contributors extending the
  DSL just add a new `check_entity/2` clause (or add a classifier rule
  in `GuardedStruct.AtomicClassifier`).
  """

  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias GuardedStruct.AtomicClassifier
  alias GuardedStruct.Dsl.{Field, SubField, ConditionalField, VirtualField}

  @impl true
  def verify(dsl_state) do
    if atomic_opted_in?(dsl_state) do
      do_verify(dsl_state)
    else
      :ok
    end
  end

  defp atomic_opted_in?(dsl_state) do
    Verifier.get_option(dsl_state, [:guardedstruct], :atomic, false) == true
  end

  defp do_verify(dsl_state) do
    entities = Verifier.get_entities(dsl_state, [:guardedstruct])
    module = Verifier.get_persisted(dsl_state, :module)
    main_validator_opt = Verifier.get_option(dsl_state, [:guardedstruct], :main_validator)

    blockers =
      collect_entities(entities, []) ++
        check_main_validator_opt(main_validator_opt) ++
        check_main_validator_callback(module)

    case blockers do
      [] -> :ok
      _ -> {:error, build_error(module, blockers)}
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # Entity walk — one pattern-match clause per entity type.
  # ────────────────────────────────────────────────────────────────────

  defp collect_entities(entities, path) do
    Enum.flat_map(entities, &check_entity(&1, path))
  end

  defp check_entity(%Field{} = f, path) do
    field_path = path ++ [f.name]

    check_ops(f.__derive_ops__, field_path) ++
      check_validator(f.validator, field_path) ++
      check_auto(f.auto, field_path) ++
      check_cross_field(f, field_path)
  end

  defp check_entity(%SubField{} = sf, path) do
    field_path = path ++ [sf.name]

    inner = collect_entities(sf.fields ++ sf.sub_fields ++ sf.conditional_fields, field_path)

    check_ops(sf.__derive_ops__, field_path) ++
      check_validator(sf.validator, field_path) ++
      check_auto(sf.auto, field_path) ++
      check_sub_main_validator(sf.main_validator, field_path) ++
      check_cross_field(sf, field_path) ++
      inner
  end

  defp check_entity(%ConditionalField{} = cf, path) do
    field_path = path ++ [cf.name]

    inner = collect_entities(cf.fields ++ cf.sub_fields ++ cf.conditional_fields, field_path)

    check_ops(cf.__derive_ops__, field_path) ++
      check_validator(cf.validator, field_path) ++
      check_auto(cf.auto, field_path) ++
      check_cross_field(cf, field_path) ++
      inner
  end

  defp check_entity(%VirtualField{} = vf, path) do
    field_path = path ++ [vf.name]

    check_ops(vf.__derive_ops__, field_path) ++
      check_validator(vf.validator, field_path) ++
      check_auto(vf.auto, field_path) ++
      check_cross_field(vf, field_path)
  end

  # Unknown entity types — be conservative.
  defp check_entity(other, path) do
    [
      {path, "unknown entity #{inspect(other)} cannot be classified for atomic mode"}
    ]
  end

  # ────────────────────────────────────────────────────────────────────
  # Per-op checks — one pattern-match clause per concern.
  # ────────────────────────────────────────────────────────────────────

  defp check_ops(nil, _path), do: []

  defp check_ops(ops, path) when is_map(ops) do
    sanitize_ops = Map.get(ops, :sanitize, []) |> Enum.map(&{:sanitize, &1})
    validate_ops = Map.get(ops, :validate, []) |> Enum.map(&{:validate, &1})

    Enum.flat_map(sanitize_ops ++ validate_ops, fn op ->
      case AtomicClassifier.classify_op(op) do
        :safe -> []
        {:unsafe, reason} -> [{path, reason}]
      end
    end)
  end

  defp check_ops(_other, _path), do: []

  defp check_validator(nil, _path), do: []

  defp check_validator({mod, fun}, path) do
    [
      {path,
       "per-field `validator: {#{inspect(mod)}, :#{fun}}` runs arbitrary " <>
         "Elixir — no SQL equivalent. Move the rule into a `derives:` " <>
         "string with built-in atomic-safe ops, or set atomic: false"}
    ]
  end

  defp check_auto(nil, _path), do: []

  defp check_auto({mod, fun}, path) do
    [
      {path,
       "`auto: {#{inspect(mod)}, :#{fun}}` runs arbitrary Elixir to " <>
         "compute the value. The data layer can't invoke user-defined " <>
         "Elixir mid-transaction"}
    ]
  end

  defp check_sub_main_validator(nil, _path), do: []

  defp check_sub_main_validator({mod, fun}, path) do
    [
      {path,
       "sub_field-level `main_validator: {#{inspect(mod)}, :#{fun}}` " <>
         "runs arbitrary Elixir across the sub_field's children"}
    ]
  end

  defp check_cross_field(entity, path) do
    cond do
      Map.get(entity, :on) ->
        [
          {path,
           "uses cross-field `on:` dependency, which requires reading " <>
             "another field's value during validation — not expressible " <>
             "as a single atomic SQL statement"}
        ]

      Map.get(entity, :from) ->
        [
          {path,
           "uses `from:` cross-field reference, which copies a value " <>
             "from another path at runtime — not atomic-safe"}
        ]

      Map.get(entity, :domain) ->
        [
          {path,
           "uses `domain:` constraint, which depends on another field's " <>
             "value — not atomic-safe"}
        ]

      true ->
        []
    end
  end

  defp check_main_validator_opt(nil), do: []

  defp check_main_validator_opt({mod, fun}) do
    [
      {[:__section__],
       "section option `main_validator: {#{inspect(mod)}, :#{fun}}` " <>
         "runs arbitrary cross-field Elixir after all field validations"}
    ]
  end

  defp check_main_validator_callback(module) when is_atom(module) do
    if function_exported?(module, :main_validator, 1) do
      [
        {[:__module__],
         "module #{inspect(module)} defines a `main_validator/1` callback. " <>
           "Cross-field validation runs arbitrary Elixir after all field " <>
           "validations and has no SQL equivalent"}
      ]
    else
      []
    end
  end

  defp check_main_validator_callback(_), do: []

  # ────────────────────────────────────────────────────────────────────
  # Error formatting.
  # ────────────────────────────────────────────────────────────────────

  defp build_error(module, blockers) do
    formatted_blockers =
      blockers
      |> Enum.map(fn {path, reason} -> "  * #{format_path(path)}: #{reason}" end)
      |> Enum.join("\n")

    Spark.Error.DslError.exception(
      path: [:guardedstruct, :atomic],
      message: """
      `atomic: true` was set on #{inspect(module)}, but the resource has
      ops that cannot run in atomic SQL mode. Either set `atomic: false`
      (the default), drop the offending ops, or use a separate action
      that doesn't require atomic.

      Blockers:
      #{formatted_blockers}

      See `GuardedStruct.AtomicClassifier` for the full list of
      atomic-safe ops.
      """
    )
  end

  defp format_path([:__section__]), do: "(section option)"
  defp format_path([:__module__]), do: "(module callback)"
  defp format_path(path), do: path |> Enum.map(&inspect/1) |> Enum.join(".")
end
