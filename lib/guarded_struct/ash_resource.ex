defmodule GuardedStruct.AshResource do
  @moduledoc """
  A Spark DSL extension that adds the GuardedStruct DSL to an Ash resource.

  ## Usage

      defmodule MyApp.User do
        use Ash.Resource,
          domain: MyApp.MyDomain,
          extensions: [GuardedStruct.AshResource]

        attributes do
          uuid_primary_key :id
          attribute :email, :string, allow_nil?: false, public?: true
        end

        # GuardedStruct DSL — identical syntax to standalone `use GuardedStruct`.
        guardedstruct do
          field :email, :string,
            derives: "sanitize(trim, downcase) validate(string, not_empty, email_r)"

          field :nickname, :string,
            derives: "sanitize(strip_tags, trim) validate(string, max_len=20)"

          sub_field :preferences, :map do
            field :theme, :string, derives: "validate(enum=String[light::dark])"
          end
        end

        # Wire the change into Ash's changeset pipeline (Option A — manual).
        changes do
          change GuardedStruct.AshResource.Change
        end
      end

  Now every `:create` and `:update` action runs the GuardedStruct pipeline
  (sanitize → validate → derive → main_validator) before Ash hits the data
  layer. Errors surface as standard `Ash.Changeset.add_error/2` errors.

  ## Two wiring modes

  ### Option A — manual (default)

  Ship-and-forget: we provide `GuardedStruct.AshResource.Change`; you add
  a one-line `changes do change ... end` block as shown above. Explicit and
  inspectable — `Ash.Resource.Info.changes/1` will show the change.

  ### Option B — auto-wire

  Set `auto_wire: true` on the section and the change is injected for you:

      guardedstruct auto_wire: true do
        field :email, :string, derives: "sanitize(trim) validate(email_r)"
      end

      # no `changes do ... end` block needed — the transformer added it

  Under the hood this calls `Ash.Resource.Builder.add_change/3` from a Spark
  transformer that runs after our codegen. The result is identical to writing
  the `changes do change ... end` block by hand — Ash's introspection sees
  the change either way. `auto_wire` is `false` by default (no magic).

  ## What this extension does NOT do

  * **It does not generate `defstruct`.** Ash already does that.
  * **It does not generate `builder/2`.** Ash uses changesets.
  * **It does not generate `Error` exception modules.** Ash has its own error
    classes (`Ash.Error.*`).

  Instead, the extension adds a single function — `__guarded_change__/1` —
  that takes a map of attrs and returns `{:ok, transformed_attrs}` or
  `{:error, errors}`. The companion `GuardedStruct.AshResource.Change` module
  wires it into the changeset; `GuardedStruct.AshResource.Info` provides
  introspection.

  ## Why `__guarded_change__` (not `__guarded_validate__`)

  Earlier drafts called the function `__guarded_validate__/1`. We renamed it
  because the function does more than validate — sanitize ops transform
  values (trim, downcase, slugify), `auto:` MFAs fill defaults, derives
  cast types. "Change" matches Ash's own terminology and is honest about
  the side-effect.

  ## Auto-map cascade

  Every nested `sub_field` returns a plain map (not a struct) at every depth
  when called through `__guarded_change__/1`. This is automatic and unique
  to the Ash extension — standalone `use GuardedStruct` callers still get
  structs from `builder/1`.

      MyResource.__guarded_change__(%{
        profile: %{address: %{geo: %{lat: 1.0, lng: 2.0}}}
      })
      # {:ok, %{profile: %{address: %{geo: %{lat: 1.0, lng: 2.0}}}}}
      #                              ^^^^ plain map, NOT a struct

  This matches Ash's `:map` attribute type, so validated output drops
  directly into `changeset.attributes` without conversion. Implementation
  is a process-local flag — concurrency-safe (sibling processes don't see
  it), re-entrancy-safe (saved+restored across nested calls), zero overhead
  for standalone callers.

  ## Update actions — `require_atomic? false`

  `GuardedStruct.AshResource.Change` runs an imperative Elixir pipeline.
  Ash 3.x's update planner requires changes to declare atomic-safety, and
  ours opts out via `atomic/3` returning `{:not_atomic, reason}`. On any
  UPDATE action that uses this change, set `require_atomic? false`:

      actions do
        update :update do
          accept [:email]
          require_atomic? false
        end
      end

  CREATE actions don't need this flag — Ash only enforces atomic mode on
  updates.

  ## sub_field vs Ash relationships

  `sub_field` inside an Ash resource creates an **embedded value type**, not
  a related Ash resource. The generated submodule is a standalone
  GuardedStruct (it has `defstruct`, `builder/1`, full GuardedStruct API)
  but it is NOT an Ash resource (no actions, no changesets, no table). Use
  `sub_field` for nested map shapes inside a single resource's attrs. For
  separate tables and relationships, use Ash's own `relationships do
  has_one :preferences, ... end`.

  ## Companion modules

  * `GuardedStruct.AshResource.Change` — the `Ash.Resource.Change` module
    that bridges `__guarded_change__/1` into the changeset pipeline.
  * `GuardedStruct.AshResource.Info` — runtime introspection for the
    `__guarded_*` namespace.

  ## Example: introspect a resource's guarded fields

      GuardedStruct.AshResource.Info.fields(MyApp.User)
      # => [:email, :nickname, :preferences]
  """

  use Spark.Dsl.Extension,
    sections: GuardedStruct.Dsl.sections(),
    transformers: [
      GuardedStruct.Transformers.ParseDerive,
      # NB: we deliberately swap the codegen transformer — the Ash variant
      # generates `__guarded_change__/1` instead of `defstruct + builder/2`
      # to avoid clashing with Ash's own machinery.
      GuardedStruct.Transformers.GenerateAshValidator,
      GuardedStruct.Transformers.GenerateSubFieldModules,
      # Optional: when `auto_wire: true` is set on the section, this
      # transformer injects a top-level `change GuardedStruct.AshResource.Change`
      # into the resource's `changes` section via `Ash.Resource.Builder.add_change/3`.
      # Default `auto_wire: false` → no-op.
      GuardedStruct.Transformers.AutoWireAshChange
    ],
    verifiers: [
      GuardedStruct.Verifiers.VerifyValidatorMFA,
      GuardedStruct.Verifiers.VerifyAutoMFA,
      GuardedStruct.Verifiers.VerifyAtomic
    ]
end
