defmodule GuardedStruct.AshResource.Change do
  @moduledoc """
  An `Ash.Resource.Change` module that plugs `__guarded_change__/1` into the
  Ash changeset pipeline.

  ## Usage

  ### Manual wiring (Option A)

      defmodule MyApp.User do
        use Ash.Resource, extensions: [GuardedStruct.AshResource]

        guardedstruct do
          field :email, :string, derives: "sanitize(trim, downcase) validate(email_r)"
        end

        changes do
          change GuardedStruct.AshResource.Change
        end
      end

  By default Ash applies the change on every `:create` and `:update` action.
  Use the standard `change ..., on: [:create]` / `where: [...]` options to
  scope it.

  ### Auto-wiring (Option B)

  Set `auto_wire: true` on the `guardedstruct` section and the change is
  injected for you — no `changes do ... end` block needed. See the
  `GuardedStruct.AshResource` moduledoc for the trade-offs.

  ## What it does

  On every fire, this change:

    1. Reads `changeset.attributes`.
    2. Calls `resource.__guarded_change__/1` — runs the full GuardedStruct
       pipeline (sanitize → validate → derive → main_validator).
    3. On `{:ok, transformed_attrs}`: calls `Ash.Changeset.force_change_attributes/2`.
    4. On `{:error, errs}`: appends each error to the changeset via
       `Ash.Changeset.add_error/2`.

  ## Ash callback support matrix

  | Callback | Supported? |
  |---|---|
  | `change/3` | ✅ |
  | `batch_change/3` | ✅ (works with `Ash.bulk_create/3` and `Ash.bulk_update/3`) |
  | `atomic/3` | ✅ but always `{:not_atomic, …}` — see below |
  | `before_batch/3` / `after_batch/3` | ❌ no-op pass-through wouldn't add value |
  | `before_action/3` / `after_action/3` | ❌ use Ash's own lifecycle hooks |
  | `validate/3` (Ash.Resource.Validation) | n/a — different behavior |

  ## Atomic mode

  `atomic/3` returns `{:not_atomic, reason}` unconditionally. The pipeline
  runs arbitrary Elixir that can't be expressed as a single SQL
  `UPDATE ... SET ...`. Users must set `require_atomic? false` on `update`
  actions that include this change. See `GuardedStruct.AtomicClassifier`
  and the `atomic: true` section option on `guardedstruct` for the
  compile-time-verified atomic path.

  ## Bulk usage

      result =
        Ash.bulk_create(input_list, MyApp.User, :create,
          return_records?: true,
          return_errors?: true
        )

  For `Ash.bulk_update/3` use `strategy: :stream` (atomic-stream isn't
  possible while our change is non-atomic).
  """

  def has_change?, do: true
  def has_atomic?, do: false
  def has_batch_change?, do: true
  def has_before_batch?, do: false
  def has_after_batch?, do: false
  def has_after_action?, do: false
  def has_before_action?, do: false
  def has_validate?, do: false
  def has_around_action?, do: false
  def has_init?, do: true

  # `atomic?/0` is what `Ash.Resource.Verifiers.VerifyActionsAtomic` checks at
  # compile time. Returning `false` AND not defining `atomic/3` makes Ash
  # raise `Spark.Error.DslError` at compile time when an action with
  # `require_atomic?: true` references this change — pointing at the action,
  # naming the change. No `atomic/3` callback is defined; Ash falls back to
  # the imperative `change/3` path automatically when atomic is not required.
  def atomic?, do: false
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
  The `Ash.Resource.Change` callback. Runs the GuardedStruct pipeline via
  `resource.__guarded_change__/1` and either applies the transformed
  attrs back to the changeset or adds errors.
  """
  def change(changeset, _opts, _context) do
    resource = changeset.resource
    attrs = changeset.attributes

    case resource.__guarded_change__(attrs) do
      {:ok, transformed_attrs} ->
        force_change_attributes(changeset, transformed_attrs)

      {:error, errs} when is_list(errs) ->
        Enum.reduce(errs, changeset, fn err, cs -> add_error(cs, to_ash_error(err)) end)

      {:error, err} ->
        add_error(changeset, to_ash_error(err))
    end
  end

  @doc """
  Bulk-action entry. Maps `change/3` over each changeset — semantic
  guarantee identical to calling `change/3` N times, one less function-call
  hop per element.
  """
  def batch_change(changesets, opts, context) do
    Enum.map(changesets, &change(&1, opts, context))
  end

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
