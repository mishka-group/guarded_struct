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

  1. Reads `changeset.attributes` (the attrs Ash has accumulated so far).
  2. Calls `resource.__guarded_change__/1` — runs the full GuardedStruct
     pipeline (sanitize → validate → derive → main_validator).
  3. On `{:ok, transformed_attrs}`: calls `Ash.Changeset.force_change_attributes/2`
     so the (possibly sanitized) values reach the data layer.
  4. On `{:error, errs}`: appends each error to the changeset via
     `Ash.Changeset.add_error/2`.

  ## Ash callback support matrix

  | Callback | Supported? | Why |
  |---|---|---|
  | `change/3` | ✅ | Primary entry — runs the pipeline per changeset |
  | `batch_change/3` | ✅ | Maps `change/3` over the list; same semantics as the per-changeset fallback Ash would use otherwise. Works with `Ash.bulk_create/3` and `Ash.bulk_update/3` |
  | `atomic/3` | ✅ but always `{:not_atomic, …}` | See below |
  | `before_batch/3` / `after_batch/3` | ❌ | No-op pass-through wouldn't add value — skip the function-call overhead |
  | `before_action/3` / `after_action/3` | ❌ | Use Ash's own lifecycle hooks alongside our change |
  | `validate/3` (Ash.Resource.Validation) | n/a | Different behavior; we're a `Change` not a `Validation` |

  ## Atomic mode

  `atomic/3` returns `{:not_atomic, reason}` unconditionally. The pipeline
  runs arbitrary Elixir (`sanitize(trim, downcase, slugify, strip_tags)`,
  `auto:` MFAs, `main_validator/1`) — none of that can be expressed as a
  single SQL `UPDATE ... SET ...` with `Ash.Expr` conditions. Users must
  set `require_atomic? false` on `update` actions that include this change.

  Pure validate-only derives (no sanitize, no auto, no main_validator)
  COULD in principle be translated to `Ash.Expr` — that's the planned
  `GuardedStruct.AshResource.Validation` companion module for the
  atomic-friendly path. Not implemented yet.

  ## Bulk usage

      result =
        Ash.bulk_create(input_list, MyApp.User, :create,
          return_records?: true,
          return_errors?: true
        )

  Sanitize runs on each input row through the imperative pipeline. There's
  no SQL-vectorized speedup (we can't SQL-batch arbitrary Elixir), but
  Ash's batch dispatch + our `batch_change/3` saves the per-changeset
  function-call hop compared to Ash falling back to `change/3` N times.

  For `Ash.bulk_update/3` use `strategy: :stream` so Ash reads the records
  through the imperative pipeline (atomic-stream isn't possible while our
  change is non-atomic).

  ## Compile-time coupling

  This module does NOT call `use Ash.Resource.Change` because that would
  force `:ash` to be in the user's deps (and ours) at compile time. Instead,
  we define `change/3` directly. Ash's DSL accepts any module that exports
  `change/3` — the `use` macro is a convenience that adds `@behaviour` plus
  default implementations of optional callbacks; it isn't strictly required.

  If you want the `@behaviour Ash.Resource.Change` check in your project,
  wrap this module:

      defmodule MyApp.GuardedChange do
        use Ash.Resource.Change
        defdelegate change(changeset, opts, context), to: GuardedStruct.AshResource.Change
      end
  """

  # Ash 3.x detects supported callbacks via `has_*/0` predicates. When you
  # `use Ash.Resource.Change`, a `@before_compile` hook generates these
  # automatically. We define them by hand to avoid the compile-time dep on
  # Ash. The values mirror what `use` would produce for a module that only
  # implements `change/3`.
  def has_change?, do: true

  # Has-atomic must be `true` because Ash 3.x calls `atomic/3` on every
  # change during update planning to decide whether to use atomic mode.
  # We answer with `{:not_atomic, reason}` to opt out per-call — that's
  # the documented escape hatch for changes that aren't atomic-safe.
  # The reason is sanitize ops (trim, downcase, slugify, strip_tags) and
  # `auto:` MFAs run arbitrary Elixir code that can't be expressed as
  # SQL/Ash.Expr. Pure-validate derives could be made atomic in principle;
  # see `GuardedStruct.AshResource.Validation` for that path.
  def has_atomic?, do: true

  # Explicit bulk support — we provide `batch_change/3` so Ash uses it
  # directly on `Ash.bulk_create/3` and `Ash.bulk_update/3` instead of
  # the per-changeset fallback. Semantically identical (each changeset
  # still gets the imperative pipeline), but skips per-element overhead.
  def has_batch_change?, do: true

  # No-op hooks — we don't transform the changeset list before/after the
  # data layer dispatch, so Ash skips these branches and saves a few
  # function calls per batch.
  def has_before_batch?, do: false
  def has_after_batch?, do: false

  def has_after_action?, do: false
  def has_before_action?, do: false
  def has_validate?, do: false
  def has_around_action?, do: false
  def has_init?, do: true

  # Ash 3.x has both `has_*?/0` and shorter `*?/0` aliases in some
  # codepaths (verifier vs. runtime). Define both forms to avoid warnings.
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
  The `Ash.Resource.Change` callback. Reads attrs from the changeset, runs
  the GuardedStruct pipeline via `resource.__guarded_change__/1`, and either
  applies the transformed attrs back or adds errors to the changeset.
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
  Bulk-action entry point. Ash invokes this for `Ash.bulk_create/3` and
  `Ash.bulk_update/3` when `has_batch_change?` is `true`. We process each
  changeset through `change/3` independently — the pipeline is per-row
  imperative, not SQL-vectorized, so there's no genuine "batch" speedup
  to extract. The semantic guarantee is: behavior identical to calling
  `change/3` N times, but with one less function-call hop per element.

  Return shape: an Enumerable of modified changesets, same length and
  order as the input.
  """
  def batch_change(changesets, opts, context) do
    Enum.map(changesets, &change(&1, opts, context))
  end

  @doc """
  Tells Ash this change is NOT atomic-safe. Ash's update planner calls
  `atomic/3` on every change during atomic-mode planning; returning
  `{:not_atomic, reason}` makes Ash fall back to the imperative `change/3`
  path.

  ## Why not atomic?

  Atomic mode pushes the change down to a single SQL `UPDATE ... SET ...`
  statement with Ash.Expr conditions. That's incompatible with the
  GuardedStruct pipeline because:

    * Sanitize ops (`trim`, `downcase`, `slugify`, `strip_tags`) execute
      arbitrary Elixir; they can't be translated to SQL `lower(...)` /
      `trim(...)` in general.
    * `auto:` MFAs run user code that returns a value the data layer
      can't compute.
    * `main_validator/1` is a free-form Elixir callback.

  Pure validate-only derives (`derives: "validate(string, max_len=80)"`)
  COULD in principle be made atomic by translating to Ash.Expr conditions.
  That requires a separate, dedicated module — see
  `GuardedStruct.AshResource.Validation` (planned).

  Users with `require_atomic? true` on an action must either set
  `require_atomic? false` or skip this change for that action via
  `change ..., on: [:create]` semantics.
  """
  def atomic(_changeset, _opts, _context) do
    {:not_atomic,
     "GuardedStruct.AshResource.Change runs an imperative sanitize/validate " <>
       "pipeline; not safe to express as atomic SQL. See moduledoc."}
  end

  # Convert a raw GuardedStruct error (a map or any term) into an
  # `Ash.Error.Changes.InvalidAttribute` so Ash wraps it as
  # `Ash.Error.Invalid` instead of `Ash.Error.Unknown`.
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
    # Ash already enforces required fields via `allow_nil?: false`. Our
    # equivalent fires when guardedstruct's enforce_keys catch a missing
    # value. Surface as a single InvalidChanges error.
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

  # Dispatched via `apply/3` so we don't reference `Ash.Changeset.*` at
  # compile time — otherwise the compiler emits "module not available"
  # warnings on projects without `:ash`. At runtime (inside a real
  # changeset) Ash is loaded and the call resolves normally.
  defp force_change_attributes(changeset, attrs),
    do: apply(Ash.Changeset, :force_change_attributes, [changeset, attrs])

  defp add_error(changeset, err),
    do: apply(Ash.Changeset, :add_error, [changeset, err])
end
