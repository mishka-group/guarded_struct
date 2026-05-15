defmodule GuardedStructTest.PropertyFixtures do
  @moduledoc """
  Small, hand-tuned fixtures targeted by the property suite under
  `test/property/`. Each module exercises a single subsystem with a
  minimal schema so generator-discovered failures localise quickly.

    * `Account` — scalars with sanitize + length-bound validators
    * `RequiredOnly` — every field `enforce: true`, for required-fields
      properties
    * `Deeply` — five-level `sub_field` chain for nesting / auto-map
      cascade properties
    * `Tagged` — `dynamic_field` of free-form metadata, for atom-attack
      and identity-preservation properties
  """

  defmodule Account do
    use GuardedStruct

    guardedstruct do
      field :email, :string,
        enforce: true,
        derives: "sanitize(trim, downcase) validate(string, not_empty, email_r, max_len=320)"

      field :nickname, :string,
        derives: "sanitize(trim) validate(string, min_len=3, max_len=24)"

      field :age, :integer, derives: "validate(integer, min_len=0, max_len=150)"
    end
  end

  defmodule RequiredOnly do
    use GuardedStruct

    guardedstruct do
      field :a, :string, enforce: true, derives: "validate(string)"
      field :b, :string, enforce: true, derives: "validate(string)"
      field :c, :string, enforce: true, derives: "validate(string)"
    end
  end

  defmodule Deeply do
    use GuardedStruct

    guardedstruct do
      field :tag, :string, derives: "sanitize(trim)"

      sub_field :l1, :map do
        field :name, :string, derives: "sanitize(trim)"

        sub_field :l2, :map do
          field :name, :string, derives: "sanitize(trim)"

          sub_field :l3, :map do
            field :name, :string, derives: "sanitize(trim)"

            sub_field :l4, :map do
              field :name, :string, derives: "sanitize(trim)"

              sub_field :l5, :map do
                field :name, :string, derives: "sanitize(trim, downcase)"
              end
            end
          end
        end
      end
    end
  end

  defmodule Tagged do
    use GuardedStruct

    guardedstruct do
      field :id, :string, enforce: true, derives: "validate(uuid)"
      dynamic_field :metadata
    end
  end
end
