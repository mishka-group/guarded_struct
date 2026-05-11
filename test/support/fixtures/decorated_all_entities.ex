defmodule GuardedStructFixtures.DecoratedAllEntities do
  @moduledoc """
  Exercises `@derives` / `@derive_rules` decorator on EVERY entity type
  and at multiple nesting depths.

  Entity coverage:
    * `field`              — top-level + inside sub_field + inside conditional_field
    * `sub_field`          — decorator on the sub_field itself
    * `conditional_field`  — decorator on the conditional_field itself + on branch fields
    * `virtual_field`      — top-level (only allowed there per DSL schema)
    * `dynamic_field`      — top-level (only allowed there per DSL schema)

  Depth coverage:
    * Level 1 (top)        — every entity type
    * Level 2 (inside sub_field) — field, sub_field, conditional_field
    * Level 3 (sub_field within sub_field) — field
    * Level 4 (sub_field within conditional inner sub_field) — field

  Each module below is small and focused on its specific decorator surface
  so failures point at exactly the case that broke.
  """

  defmodule Validators do
    @moduledoc false
    def is_string(field, v) when is_binary(v), do: {:ok, field, v}
    def is_string(field, _), do: {:error, field, "not a string"}

    def is_map(field, v) when is_map(v) and not is_struct(v), do: {:ok, field, v}
    def is_map(field, _), do: {:error, field, "not a map"}
  end

  # ----------------------------------------------------------------
  # 1. @derives on `field` — the baseline case
  # ----------------------------------------------------------------
  defmodule OnField do
    use GuardedStruct

    guardedstruct do
      @derives "sanitize(trim) validate(string, max_len=10)"
      field(:name, String.t())
    end
  end

  # ----------------------------------------------------------------
  # 2. @derives on `virtual_field` — validated but not in struct
  # ----------------------------------------------------------------
  defmodule OnVirtualField do
    use GuardedStruct

    guardedstruct do
      field(:keep, String.t(), enforce: true)

      @derives "validate(string, min_len=8)"
      virtual_field(:password_confirmation, String.t())
    end

    # main_validator/1 auto-discovered — uses the virtual field
    def main_validator(%{password_confirmation: pw} = attrs) when is_binary(pw),
      do: {:ok, attrs}

    def main_validator(_),
      do:
        {:error,
         [%{field: :password_confirmation, action: :missing, message: "confirmation required"}]}
  end

  # ----------------------------------------------------------------
  # 3. @derives on `dynamic_field` — overrides default `validate(map)`
  # ----------------------------------------------------------------
  defmodule OnDynamicField do
    use GuardedStruct

    guardedstruct do
      # `dynamic_field` defaults to `derives: "validate(map)"`. The decorator
      # injects via `derives:`, which wins over the schema default.
      @derives "validate(map, not_empty)"
      dynamic_field(:metadata)
    end
  end

  # ----------------------------------------------------------------
  # 4. @derives on `sub_field` itself (the OUTER decorator)
  # ----------------------------------------------------------------
  defmodule OnSubField do
    use GuardedStruct

    guardedstruct do
      @derives "validate(map)"
      sub_field(:profile, struct()) do
        field(:bio, String.t())
      end
    end
  end

  # ----------------------------------------------------------------
  # 5. @derives on `conditional_field` itself
  #
  # The decorator's derive enforces BEFORE branch resolution. So
  # `@derives "validate(map)"` here means the value MUST be a map —
  # both branches accept maps, but with different inner shapes.
  # ----------------------------------------------------------------
  defmodule OnConditionalField do
    use GuardedStruct

    guardedstruct do
      @derives "validate(map)"
      conditional_field(:detail, any()) do
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
  # 6. @derives on a `field` INSIDE a sub_field body (level 2)
  # ----------------------------------------------------------------
  defmodule InsideSubField do
    use GuardedStruct

    guardedstruct do
      sub_field(:wrapper, struct()) do
        @derives "sanitize(trim) validate(string, max_len=5)"
        field(:tag, String.t())
      end
    end
  end

  # ----------------------------------------------------------------
  # 7. @derives on a `field` inside a `conditional_field` BRANCH
  # ----------------------------------------------------------------
  defmodule InsideConditional do
    use GuardedStruct

    guardedstruct do
      conditional_field(:body, any()) do
        @derives "validate(string, max_len=10)"
        field(:body, String.t(),
          hint: "short_string",
          validator: {Validators, :is_string}
        )

        # No decorator on this branch — uses inline rules
        sub_field(:body, struct(),
          hint: "map_form",
          validator: {Validators, :is_map}
        ) do
          @derives "validate(string)"
          field(:kind, String.t())
        end
      end
    end
  end

  # ----------------------------------------------------------------
  # 8. DEEP nesting — @derives at every level (1 → 2 → 3 → 4)
  # ----------------------------------------------------------------
  defmodule DeepNested do
    use GuardedStruct

    guardedstruct do
      @derives "validate(string, max_len=10)"
      field(:top, String.t())                                     # level 1

      @derives "validate(map)"
      sub_field(:l1, struct()) do                                 # level 1 on sub_field
        @derives "validate(string, max_len=20)"
        field(:tag, String.t())                                   # level 2

        sub_field(:l2, struct()) do
          @derives "validate(string, max_len=30)"
          field(:tag, String.t())                                 # level 3

          sub_field(:l3, struct()) do
            @derives "validate(string, max_len=40)"
            field(:tag, String.t())                               # level 4
          end
        end
      end
    end
  end

  # ----------------------------------------------------------------
  # 9. Mixed-entity module — every entity type in one module
  # ----------------------------------------------------------------
  defmodule MixedAll do
    use GuardedStruct

    guardedstruct do
      @derives "validate(string)"
      field(:plain, String.t())

      @derives "validate(map)"
      dynamic_field(:extras)

      @derives "validate(string, min_len=3)"
      virtual_field(:totp, String.t())

      @derives "validate(map)"
      sub_field(:nested, struct()) do
        @derives "validate(string, max_len=10)"
        field(:label, String.t())
      end

      # No @derives on the conditional itself here — would block strings.
      # We keep this conditional permissive so the string branch can win
      # for non-map inputs. The decorator on the inner sub_field's field
      # still demonstrates inside-conditional decoration.
      conditional_field(:variant, any()) do
        field(:variant, String.t(),
          hint: "string",
          validator: {Validators, :is_string}
        )

        sub_field(:variant, struct(),
          hint: "map",
          validator: {Validators, :is_map}
        ) do
          @derives "validate(string)"
          field(:value, String.t())
        end
      end
    end

    def main_validator(%{totp: t} = attrs) when is_binary(t) and byte_size(t) >= 3,
      do: {:ok, attrs}

    def main_validator(_),
      do:
        {:error,
         [%{field: :totp, action: :missing, message: "totp required"}]}
  end
end
