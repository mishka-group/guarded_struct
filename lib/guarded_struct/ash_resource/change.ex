defmodule GuardedStruct.AshResource.Change do
  @moduledoc """
  An `Ash.Resource.Change` module that plugs `__guarded_change__/1` into the
  Ash changeset pipeline.

  ## Usage

  ### Manual wiring

      defmodule MyApp.User do
        use Ash.Resource, extensions: [GuardedStruct.AshResource]

        guardedstruct do
          field :email, :string, derives: "sanitize(trim, downcase) validate(email_r)"
        end

        changes do
          change GuardedStruct.AshResource.Change
        end
      end

  ### Auto-wiring

  Set `auto_wire: true` on the `guardedstruct` section and the change is
  injected automatically — no `changes do ... end` block needed.

  ## Atomic mode

  `atomic/3` runs the GuardedStruct pipeline in Elixir on the plain
  literal values Ash placed in `changeset.attributes` and
  `changeset.atomics`, then returns `{:atomic, sanitized_map}` — the
  shape Ash uses to substitute pre-computed values into the single SQL
  statement. The action stays atomic (one UPDATE, no extra round-trip)
  and the persisted value is the sanitized one.

  This means sanitize / validate / derive / `auto:` MFAs / custom
  `Derive.Extension` ops all work in atomic mode. The only blocker is
  when the user explicitly provides an `Ash.Expr` for a field via
  `Ash.Changeset.atomic_update/3`:

      Ash.Changeset.atomic_update(record, :counter, expr(counter + 1))

  In that case we can't sanitize a value we won't know until the SQL
  evaluates, so `atomic/3` returns `{:not_atomic, reason}` and Ash
  falls back to the imperative path. This is rare in practice — 99% of
  changesets pass plain literals.

  No `require_atomic? false` flag is needed on update / destroy actions.

  ## Bulk operations

      Ash.bulk_create(input_list, MyApp.User, :create,
        return_records?: true,
        return_errors?: true
      )

  `Ash.bulk_update/3` also works — `strategy: :atomic` (the default) uses
  our atomic pattern; `strategy: :stream` uses the imperative `change/3`
  path. Both produce identical results.
  """

  def has_change?, do: true
  def has_atomic?, do: true
  def has_batch_change?, do: true
  def has_before_batch?, do: false
  def has_after_batch?, do: false
  def has_after_action?, do: false
  def has_before_action?, do: false
  def has_validate?, do: false
  def has_around_action?, do: false
  def has_init?, do: true

  def atomic?, do: true
  def batch_change?, do: true
  def before_batch?, do: false
  def after_batch?, do: false
  def after_action?, do: false
  def before_action?, do: false
  def validate?, do: false
  def around_action?, do: false

  @doc false
  def init(opts), do: {:ok, opts}

  @doc false
  def batch_callbacks?(_, _, _), do: true

  @doc """
  The `Ash.Resource.Change` callback for the non-atomic / regular-change
  path. Runs the GuardedStruct pipeline on `changeset.attributes` and
  applies the transformed values back, or adds errors.
  """
  def change(changeset, _opts, _context) do
    apply_pipeline(changeset)
  end

  @doc """
  The atomic-mode callback.

    * If any field's atomic value is an `Ash.Expr`, bail with
      `{:not_atomic, reason}` — we can't transform a value we won't
      know until the SQL evaluates.
    * Otherwise, run the GuardedStruct pipeline on the combined
      `attributes` + `atomics` literals and return
      `{:atomic, sanitized_map}` for Ash to substitute into the
      single-statement UPDATE.
  """
  def atomic(changeset, _opts, _context) do
    attrs = changeset.attributes || %{}
    atomics_map = atomics_to_map(changeset)

    expr_keys =
      atomics_map
      |> Enum.filter(fn {_k, v} -> ash_expr?(v) end)
      |> Enum.map(fn {k, _v} -> k end)

    cond do
      expr_keys != [] ->
        {:not_atomic,
         "fields #{inspect(expr_keys)} were provided as Ash.Expr in " <>
           "changeset.atomics — the GuardedStruct pipeline can't " <>
           "sanitize/validate a value it won't see until the SQL evaluates"}

      map_size(attrs) == 0 and map_size(atomics_map) == 0 ->
        :ok

      true ->
        run_atomic(changeset, Map.merge(atomics_map, attrs))
    end
  end

  defp atomics_to_map(changeset) do
    case Map.get(changeset, :atomics) do
      nil -> %{}
      list when is_list(list) -> Map.new(list)
      map when is_map(map) -> map
      _ -> %{}
    end
  end

  defp ash_expr?(value) do
    Code.ensure_loaded?(Ash.Expr) and apply(Ash.Expr, :expr?, [value])
  end

  @doc """
  Bulk-action entry. Maps `change/3` over each changeset.
  """
  def batch_change(changesets, opts, context) do
    Enum.map(changesets, &change(&1, opts, context))
  end

  # Imperative change path — `change/3`. `force_change_attribute` is fine
  # here because Ash's non-atomic pipeline reads attributes from the
  # changeset before issuing SQL.
  defp apply_pipeline(changeset) do
    resource = changeset.resource
    attrs = changeset.attributes

    case resource.__guarded_change__(attrs) do
      {:ok, transformed_attrs} ->
        force_change_attributes(changeset, transformed_attrs)

      {:error, errs} when is_list(errs) ->
        errs = maybe_filter_required(errs, changeset.action_type)
        Enum.reduce(errs, changeset, fn err, cs -> add_error(cs, to_ash_error(err)) end)

      {:error, err} ->
        add_error(changeset, to_ash_error(err))
    end
  end

  # Atomic change path — returns `{:atomic, %{attr => value}}` directly,
  # which is the shape Ash accepts for atomic-SQL substitution. Plain
  # values are fine (Ash casts them through the attribute type); we only
  # use Ash.Expr when we need data-layer-side computation.
  defp run_atomic(changeset, input_attrs) do
    resource = changeset.resource

    case resource.__guarded_change__(input_attrs) do
      {:ok, transformed_attrs} ->
        atomic_map = Map.take(transformed_attrs, Map.keys(input_attrs))

        if map_size(atomic_map) == 0 do
          :ok
        else
          {:atomic, atomic_map}
        end

      {:error, errs} when is_list(errs) ->
        errs = maybe_filter_required(errs, changeset.action_type)

        if errs == [] do
          :ok
        else
          cs = Enum.reduce(errs, changeset, fn err, c -> add_error(c, to_ash_error(err)) end)
          {:ok, cs}
        end

      {:error, err} ->
        {:ok, add_error(changeset, to_ash_error(err))}
    end
  end

  # On UPDATE / DESTROY actions the user provides only a subset of
  # attributes — fields not in the changeset shouldn't trigger required
  # errors (Ash already enforces required-ness via `allow_nil?` on the
  # attribute schema). Drop `:required_fields` errors for updates.
  defp maybe_filter_required(errs, :update),
    do: Enum.reject(errs, &(Map.get(&1, :action) == :required_fields))

  defp maybe_filter_required(errs, :destroy),
    do: Enum.reject(errs, &(Map.get(&1, :action) == :required_fields))

  defp maybe_filter_required(errs, _), do: errs

  # `apply/3` defers the Ash.* references to runtime so the module
  # compiles without warnings when Ash isn't in the user's deps.
  defp force_change_attributes(changeset, attrs),
    do: apply(Ash.Changeset, :force_change_attributes, [changeset, attrs])

  defp add_error(changeset, err),
    do: apply(Ash.Changeset, :add_error, [changeset, err])

  defp to_ash_error(%{field: field, message: message} = err) do
    apply(Ash.Error.Changes.InvalidAttribute, :exception, [
      [
        field: field,
        message: message,
        value: Map.get(err, :value),
        vars: vars_for(err)
      ]
    ])
  end

  defp to_ash_error(%{fields: fields, action: :required_fields} = _err) do
    apply(Ash.Error.Changes.InvalidChanges, :exception, [
      [
        fields: fields,
        message: "required by guardedstruct: #{Enum.join(fields, ", ")}"
      ]
    ])
  end

  defp to_ash_error(other), do: other

  defp vars_for(%{action: action}) when is_atom(action), do: [validation: action]
  defp vars_for(_), do: []
end
