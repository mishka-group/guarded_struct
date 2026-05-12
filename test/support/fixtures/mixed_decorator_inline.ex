defmodule GuardedStructFixtures.MixedDecoratorInline do
  @moduledoc """
  Fixtures combining the two `derives:` syntactic forms (decorator
  `@derives "..."` and inline `derives: "..."`) in various arrangements
  to prove they coexist and produce equivalent results.

  Covers:
    * Decorator on field A + inline on field B at the same level
    * Decorator on outer sub_field + inline on inner field
    * Inline on outer sub_field + decorator on inner field
    * Both forms present on the SAME field (inline wins)
    * Adjacent virtual_field decorator + inline (each enforced independently)
  """

  defmodule Validators do
    @moduledoc false
    def is_string(field, v) when is_binary(v), do: {:ok, field, v}
    def is_string(field, _), do: {:error, field, "not a string"}

    def is_map(field, v) when is_map(v) and not is_struct(v), do: {:ok, field, v}
    def is_map(field, _), do: {:error, field, "not a map"}
  end

  # ----------------------------------------------------------------
  # 1. Two siblings — decorator on one, inline on the other
  # ----------------------------------------------------------------
  defmodule SiblingMix do
    use GuardedStruct

    guardedstruct do
      @derives "validate(string, max_len=5)"
      field(:short_name, String.t())

      field(:long_name, String.t(), derives: "validate(string, max_len=50)")
    end
  end

  # ----------------------------------------------------------------
  # 2. Decorator on outer sub_field + inline on inner field
  # ----------------------------------------------------------------
  defmodule OuterDecoratorInnerInline do
    use GuardedStruct

    guardedstruct do
      @derives "validate(map)"
      sub_field(:profile, struct()) do
        field(:nickname, String.t(), derives: "validate(string, max_len=20)")
      end
    end
  end

  # ----------------------------------------------------------------
  # 3. Inline on outer sub_field + decorator on inner field
  # ----------------------------------------------------------------
  defmodule OuterInlineInnerDecorator do
    use GuardedStruct

    guardedstruct do
      sub_field(:profile, struct(), derives: "validate(map)") do
        @derives "validate(string, max_len=20)"
        field(:nickname, String.t())
      end
    end
  end

  # ----------------------------------------------------------------
  # 4. BOTH on the same field — inline wins (existing precedence rule)
  # ----------------------------------------------------------------
  defmodule BothOnSameField do
    use GuardedStruct

    guardedstruct do
      @derives "validate(string, max_len=5)"
      field(:name, String.t(), derives: "validate(string, max_len=100)")
    end
  end

  # ----------------------------------------------------------------
  # 5. Adjacent virtual_field — decorator on one, inline on the other.
  # Confirms decorator one-shot semantics + independent enforcement.
  # ----------------------------------------------------------------
  defmodule VirtualMix do
    use GuardedStruct

    guardedstruct do
      field(:keep, String.t(), enforce: true)

      @derives "validate(string, min_len=4)"
      virtual_field(:totp_a, String.t())

      virtual_field(:totp_b, String.t(), derives: "validate(string, min_len=6)")
    end

    def main_validator(%{totp_a: a, totp_b: b} = attrs)
        when is_binary(a) and is_binary(b),
        do: {:ok, attrs}

    def main_validator(_attrs),
      do:
        {:error,
         [%{field: :virtual, action: :missing, message: "totp_a and totp_b required"}]}
  end

  # ----------------------------------------------------------------
  # 6. Mixed conditional — decorator on conditional + inline on branch field
  # ----------------------------------------------------------------
  defmodule ConditionalMix do
    use GuardedStruct

    guardedstruct do
      @derives "validate(map)"
      conditional_field(:detail, any()) do
        sub_field(:detail, struct(),
          hint: "minimal",
          validator: {Validators, :is_map}
        ) do
          field(:tag, String.t(), derives: "validate(string, max_len=8)")
        end
      end
    end
  end
end
