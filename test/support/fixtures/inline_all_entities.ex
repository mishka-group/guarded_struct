defmodule GuardedStructFixtures.InlineAllEntities do
  @moduledoc """
  Inline `derives:` opt on EVERY entity type at multiple nesting depths —
  mirrors `DecoratedAllEntities` but uses the keyword-list form instead
  of the `@derives` attribute decorator.

  After the virtual_field two-pass derive fix in Runtime, **all 5 entity
  types now enforce their `derives:` rules at runtime**, regardless of
  whether the rule was written inline or via the decorator.

  Modules below cover:
    * `field`              — top-level, inside sub_field, inside conditional branch
    * `virtual_field`      — top-level (only allowed there per DSL schema)
    * `dynamic_field`      — top-level (only allowed there per DSL schema)
    * `sub_field`          — both on the sub_field itself AND on inner fields
    * `conditional_field`  — on the conditional itself + on branch fields
    * Deep nesting (levels 1 → 2 → 3 → 4)
  """

  defmodule Validators do
    @moduledoc false
    def is_string(field, v) when is_binary(v), do: {:ok, field, v}
    def is_string(field, _), do: {:error, field, "not a string"}

    def is_map(field, v) when is_map(v) and not is_struct(v), do: {:ok, field, v}
    def is_map(field, _), do: {:error, field, "not a map"}
  end

  # ----------------------------------------------------------------
  # 1. inline derives: on `field`
  # ----------------------------------------------------------------
  defmodule OnField do
    use GuardedStruct

    guardedstruct do
      field(:name, String.t(), derives: "sanitize(trim) validate(string, max_len=10)")
    end
  end

  # ----------------------------------------------------------------
  # 2. inline derives: on `virtual_field`
  # ----------------------------------------------------------------
  defmodule OnVirtualField do
    use GuardedStruct

    guardedstruct do
      field(:keep, String.t(), enforce: true)
      virtual_field(:password_confirmation, String.t(),
        derives: "validate(string, min_len=8)"
      )
    end

    def main_validator(%{password_confirmation: pw} = attrs) when is_binary(pw),
      do: {:ok, attrs}

    def main_validator(_),
      do:
        {:error,
         [%{field: :password_confirmation, action: :missing, message: "required"}]}
  end

  # ----------------------------------------------------------------
  # 3. inline derives: on `dynamic_field` (overrides schema default)
  # ----------------------------------------------------------------
  defmodule OnDynamicField do
    use GuardedStruct

    guardedstruct do
      dynamic_field(:metadata, derives: "validate(map, not_empty)")
    end
  end

  # ----------------------------------------------------------------
  # 4. inline derives: on `sub_field` itself
  # ----------------------------------------------------------------
  defmodule OnSubField do
    use GuardedStruct

    guardedstruct do
      sub_field(:profile, struct(), derives: "validate(map)") do
        field(:bio, String.t())
      end
    end
  end

  # ----------------------------------------------------------------
  # 5. inline derives: on `conditional_field` itself
  # ----------------------------------------------------------------
  defmodule OnConditionalField do
    use GuardedStruct

    guardedstruct do
      conditional_field(:detail, any(), derives: "validate(map)") do
        sub_field(:detail, struct(),
          hint: "minimal",
          validator: {Validators, :is_map}
        ) do
          field(:tag, String.t())
        end

        sub_field(:detail, struct(),
          hint: "full",
          validator: {Validators, :is_map}
        ) do
          field(:tag, String.t(), enforce: true)
          field(:extra, String.t())
        end
      end
    end
  end

  # ----------------------------------------------------------------
  # 6. inline derives: on field INSIDE a sub_field body
  # ----------------------------------------------------------------
  defmodule InsideSubField do
    use GuardedStruct

    guardedstruct do
      sub_field(:wrapper, struct()) do
        field(:tag, String.t(), derives: "sanitize(trim) validate(string, max_len=5)")
      end
    end
  end

  # ----------------------------------------------------------------
  # 7. inline derives: on branch fields of conditional_field
  # ----------------------------------------------------------------
  defmodule InsideConditional do
    use GuardedStruct

    guardedstruct do
      conditional_field(:body, any()) do
        field(:body, String.t(),
          hint: "short_string",
          validator: {Validators, :is_string},
          derives: "validate(string, max_len=10)"
        )

        sub_field(:body, struct(),
          hint: "map_form",
          validator: {Validators, :is_map}
        ) do
          field(:kind, String.t(), derives: "validate(string)")
        end
      end
    end
  end

  # ----------------------------------------------------------------
  # 8. DEEP nesting — inline derives: at every level (1 → 2 → 3 → 4)
  # ----------------------------------------------------------------
  defmodule DeepNested do
    use GuardedStruct

    guardedstruct do
      field(:top, String.t(), derives: "validate(string, max_len=10)")

      sub_field(:l1, struct(), derives: "validate(map)") do
        field(:tag, String.t(), derives: "validate(string, max_len=20)")

        sub_field(:l2, struct()) do
          field(:tag, String.t(), derives: "validate(string, max_len=30)")

          sub_field(:l3, struct()) do
            field(:tag, String.t(), derives: "validate(string, max_len=40)")
          end
        end
      end
    end
  end

  # ----------------------------------------------------------------
  # 9. Mixed-entity module — every entity type, inline form
  # ----------------------------------------------------------------
  defmodule MixedAll do
    use GuardedStruct

    guardedstruct do
      field(:plain, String.t(), derives: "validate(string)")
      dynamic_field(:extras, derives: "validate(map)")
      virtual_field(:totp, String.t(), derives: "validate(string, min_len=3)")

      sub_field(:nested, struct(), derives: "validate(map)") do
        field(:label, String.t(), derives: "validate(string, max_len=10)")
      end

      conditional_field(:variant, any()) do
        field(:variant, String.t(),
          hint: "string",
          validator: {Validators, :is_string}
        )

        sub_field(:variant, struct(),
          hint: "map",
          validator: {Validators, :is_map}
        ) do
          field(:value, String.t(), derives: "validate(string)")
        end
      end
    end
  end
end
