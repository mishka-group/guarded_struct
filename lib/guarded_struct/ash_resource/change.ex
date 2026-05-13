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
        Enum.reduce(errs, changeset, &add_error(&2, &1))

      {:error, err} ->
        add_error(changeset, err)
    end
  end

  # Dispatched via `apply/3` so we don't reference `Ash.Changeset.*` at
  # compile time — otherwise the compiler emits "module not available"
  # warnings on projects without `:ash`. At runtime (inside a real
  # changeset) Ash is loaded and the call resolves normally.
  defp force_change_attributes(changeset, attrs),
    do: apply(Ash.Changeset, :force_change_attributes, [changeset, attrs])

  defp add_error(changeset, err),
    do: apply(Ash.Changeset, :add_error, [changeset, err])
end
