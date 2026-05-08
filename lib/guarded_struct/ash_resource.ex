defmodule GuardedStruct.AshResource do
  @moduledoc """
  A Spark DSL extension that adds the GuardedStruct DSL to an Ash resource.

  ## Usage

      defmodule MyApp.User do
        use Ash.Resource,
          domain: MyApp.MyDomain,
          extensions: [GuardedStruct.AshResource]

        # ...the standard Ash sections...
        attributes do
          uuid_primary_key :id
          attribute :email, :string, allow_nil?: false, public?: true
        end

        # NEW: a guardedstruct block, identical syntax to standalone
        # `use GuardedStruct`. Defines field-level sanitize/validate/derive
        # rules that Ash actions can reach via `__guarded_validate__/1`.
        guardedstruct do
          field :email, :string,
            derive: "sanitize(trim, downcase) validate(string, not_empty, email_r)"

          field :nickname, :string,
            derive: "sanitize(strip_tags, trim) validate(string, max_len=20)"

          sub_field :preferences, :map do
            field :theme, :string, derive: "validate(enum=String[light::dark])"
          end
        end
      end

      # In an action change, you can call:
      MyApp.User.__guarded_validate__(attrs)
      # => {:ok, sanitized_attrs} | {:error, errors}

  ## Why this exists

  Ash resources already have `attributes`, `validations`, and `changes`. The
  GuardedStruct DSL is complementary — it bundles a richer mini-language for
  derive/sanitize/validate rules, plus structural features (`conditional_field`,
  the four core keys) that Ash's own DSL doesn't have first-class equivalents
  for.

  ## What this extension does NOT do

  * **It does not generate `defstruct`.** Ash already does that.
  * **It does not generate `builder/2`.** Ash uses changesets.
  * **It does not generate `Error` exception modules.** Ash has its own error
    classes (`Ash.Error.*`).

  Instead, the extension adds a single function — `__guarded_validate__/1` —
  that takes a map of attrs and returns `{:ok, validated_attrs}` or
  `{:error, errors}`. Wire it into a `Ash.Resource.Change` or a
  `Ash.Resource.Validation` to plug into Ash's pipeline.

  Use the companion `GuardedStruct.AshResource.Info` module to introspect the
  guardedstruct block at runtime:

      GuardedStruct.AshResource.Info.fields(MyApp.User)
      # => [:email, :nickname, :preferences]
  """

  use Spark.Dsl.Extension,
    sections: GuardedStruct.Dsl.sections(),
    transformers: [
      GuardedStruct.Transformers.ParseDerive,
      # NB: we deliberately swap the codegen transformer — the Ash variant
      # generates `__guarded_validate__/1` instead of `defstruct + builder/2`
      # to avoid clashing with Ash's own machinery.
      GuardedStruct.Transformers.GenerateAshValidator,
      GuardedStruct.Transformers.GenerateSubFieldModules
    ],
    verifiers: [
      GuardedStruct.Verifiers.VerifyValidatorMFA,
      GuardedStruct.Verifiers.VerifyAutoMFA
    ]
end
