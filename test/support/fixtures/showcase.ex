defmodule GuardedStructFixtures.Showcase do
  @moduledoc """
  The "everything-at-once" showcase: an `EnterpriseAccount` that exercises
  most of 0.1.0's new surface in a single coherent schema.

  Combines:
    * `jason: true` — JSON-encodable for API
    * `@derives` decorator — clean DSL
    * `virtual_field` — `:invitation_token` validated but not persisted
    * `auto:` — `:id` minted at build time, `:created_at` timestamped
    * `from:` — `:owner_email` pulled from the embedded `:owner` sub_field
    * `dynamic_field` — `:settings` is an open map
    * `sub_field` with `structs: true` — list of `Member`s
    * Nested `conditional_field` — `:plan` is either a string preset OR a
      detailed map, and the detailed map's `:overrides` is itself a
      conditional (map OR list of overrides)
    * `main_validator/1` auto-discovery — enforces invitation token length
    * `Schema.json_schema/1` / `Schema.openapi/1` work over this shape
    * `Diff.diff/2` / `Validate.partial/2` work over this shape
  """

  alias GuardedStructFixtures.CustomDerives.MyDerives
  _ = MyDerives

  defmodule Validators do
    @moduledoc false
    def is_string(field, v) when is_binary(v), do: {:ok, field, v}
    def is_string(field, _), do: {:error, field, "not a string"}

    def is_map(field, v) when is_map(v) and not is_struct(v), do: {:ok, field, v}
    def is_map(field, _), do: {:error, field, "not a map"}

    def is_list(field, v) when is_list(v), do: {:ok, field, v}
    def is_list(field, _), do: {:error, field, "not a list"}
  end

  defmodule Member do
    use GuardedStruct

    guardedstruct do
      @derives "validate(uuid)"
      field(:id, String.t(), enforce: true)

      @derives "sanitize(trim, downcase) validate(string, email_r)"
      field(:email, String.t(), enforce: true)

      @derives "validate(enum=String[owner::admin::member::viewer])"
      field(:role, String.t(), default: "member")
    end
  end

  defmodule EnterpriseAccount do
    use GuardedStruct

    guardedstruct jason: true do
      field(:id, String.t(), auto: {GuardedStructTest.Support.UUID, :generate})

      @derives "sanitize(trim) validate(string, not_empty, max_len=100)"
      field(:name, String.t(), enforce: true)

      sub_field(:owner, struct(), enforce: true) do
        @derives "validate(uuid)"
        field(:id, String.t(), enforce: true)

        @derives "sanitize(trim, downcase) validate(string, email_r)"
        field(:email, String.t(), enforce: true)
      end

      # Pulled from owner.email
      field(:owner_email, String.t(), from: "root::owner::email")

      sub_field(:members, list(struct()), structs: true) do
        @derives "validate(uuid)"
        field(:id, String.t(), enforce: true)

        @derives "sanitize(trim, downcase) validate(string, email_r)"
        field(:email, String.t(), enforce: true)

        @derives "validate(enum=String[owner::admin::member::viewer])"
        field(:role, String.t(), default: "member")
      end

      # Plan is either a preset string OR a sub_field with a detailed shape
      # whose `:notes` field is itself a string-or-list conditional.
      # This exercises the headline 0.1.0 fix: conditional_field nested
      # inside a sub_field that's a branch of a conditional_field.
      conditional_field(:plan, any()) do
        field(:plan, String.t(),
          hint: "preset",
          validator: {Validators, :is_string},
          derives: "validate(enum=String[free::pro::enterprise])"
        )

        sub_field(:plan, struct(),
          hint: "detailed",
          validator: {Validators, :is_map}
        ) do
          field(:tier, String.t(),
            enforce: true,
            derives: "validate(enum=String[pro::enterprise::custom])"
          )

          field(:seat_count, integer(), derives: "validate(integer)")

          # Inner conditional: notes is a string OR a list of strings.
          conditional_field(:notes, any()) do
            field(:notes, String.t(),
              hint: "single",
              validator: {Validators, :is_string},
              derives: "validate(string, max_len=500)"
            )

            field(:notes, list(),
              hint: "many",
              validator: {Validators, :is_list},
              derives: "validate(list)"
            )
          end
        end
      end

      dynamic_field(:settings)

      virtual_field(:invitation_token, String.t(), derives: "validate(string, min_len=16)")
    end

    def main_validator(%{invitation_token: t} = attrs) when is_binary(t) do
      # Token is required to be present-and-valid AT BUILD TIME, then dropped.
      if String.length(t) >= 16, do: {:ok, attrs}, else: bad_token()
    end

    def main_validator(_), do: bad_token()

    defp bad_token,
      do:
        {:error,
         [%{field: :invitation_token, action: :missing, message: "invitation_token required"}]}
  end
end
