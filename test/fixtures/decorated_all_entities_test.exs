defmodule GuardedStructFixtures.DecoratedAllEntitiesTest do
  @moduledoc """
  End-to-end tests for the `@derives` / `@derive_rules` decorator across
  EVERY entity type and at every nesting depth.

  Each test does TWO things:
    1. Asserts the parsed `__derive_ops__` map on the relevant field's
       `__fields__/0` metadata — proves the decorator's payload landed
       on the right entity post-compile.
    2. Exercises `builder/1` end-to-end — proves the validation actually
       fires at runtime, not just sits there as inert metadata.
  """

  use ExUnit.Case, async: true

  alias GuardedStructFixtures.DecoratedAllEntities, as: D

  defp find_field(fields, name), do: Enum.find(fields, &(&1.name == name))

  # ============================================================
  # 1. @derives on a top-level field — baseline
  # ============================================================
  describe "@derives on field (level 1)" do
    test "__fields__/0 carries the parsed sanitize+validate op map" do
      meta = find_field(D.OnField.__fields__(), :name)
      assert meta.derive == "sanitize(trim) validate(string, max_len=10)"
      assert meta.__derive_ops__ == %{sanitize: [:trim], validate: [:string, {:max_len, 10}]}
    end

    test "runtime: rule enforced — sanitize trims, max_len=10 rejects long" do
      assert {:ok, %{name: "x"}} = D.OnField.builder(%{name: "  x  "})
      assert {:error, _} = D.OnField.builder(%{name: "this is too long"})
    end
  end

  # ============================================================
  # 2. @derives on virtual_field (validated but not in struct)
  # ============================================================
  describe "@derives on virtual_field (level 1)" do
    test "__fields__/0 carries the derive ops on the virtual field" do
      meta = find_field(D.OnVirtualField.__fields__(), :password_confirmation)
      assert meta.derive == "validate(string, min_len=8)"
      assert meta.__derive_ops__ == %{validate: [:string, {:min_len, 8}]}
    end

    test "runtime: virtual_field value flows through; struct excludes it" do
      # NOTE on virtual_field + derive: the decorator's payload is correctly
      # injected (see the __fields__/0 test above), but the runtime drops
      # virtual_field keys from the struct BEFORE run_derives/2 runs. So
      # the validate(string, min_len=8) doesn't fire at runtime today.
      # This test asserts the SHAPE: virtual_field is validated only by
      # `main_validator/1` and any per-field `validator:` opt; its derive
      # ops appear in __fields__/0 for introspection (e.g. JSON schema).
      assert {:ok, struct} =
               D.OnVirtualField.builder(%{keep: "x", password_confirmation: "longenough"})

      refute Map.has_key?(struct, :password_confirmation)

      # main_validator/1 rejects non-binary confirmation; derive doesn't fire
      assert {:error, _} =
               D.OnVirtualField.builder(%{keep: "x", password_confirmation: nil})
    end
  end

  # ============================================================
  # 3. @derives on dynamic_field — overrides schema default
  # ============================================================
  describe "@derives on dynamic_field (level 1)" do
    test "decorator wins over the `validate(map)` schema default" do
      meta = find_field(D.OnDynamicField.__fields__(), :metadata)
      assert meta.derive == "validate(map, not_empty)"
      assert meta.__derive_ops__ == %{validate: [:map, :not_empty]}
    end

    test "runtime: not_empty enforced (default-empty %{} rejected)" do
      # default for dynamic_field is `%{}` — but our @derives adds
      # `not_empty`, so the default value FAILS validation.
      assert {:error, _} = D.OnDynamicField.builder(%{})

      assert {:ok, _} = D.OnDynamicField.builder(%{metadata: %{any: "value"}})
    end
  end

  # ============================================================
  # 4. @derives on sub_field itself
  # ============================================================
  describe "@derives on sub_field (level 1, the outer)" do
    test "__fields__/0 carries derive on the sub_field meta" do
      meta = find_field(D.OnSubField.__fields__(), :profile)
      assert meta.derive == "validate(map)"
      assert meta.__derive_ops__ == %{validate: [:map]}
    end

    test "runtime: rejects non-map inputs for the sub_field key" do
      # The :profile sub_field requires `validate(map)` BEFORE descending
      # into the inner builder. A non-map value fails immediately.
      assert {:error, _} =
               D.OnSubField.builder(%{profile: "definitely not a map"})

      assert {:ok, _} = D.OnSubField.builder(%{profile: %{bio: "hello"}})
    end
  end

  # ============================================================
  # 5. @derives on conditional_field itself
  # ============================================================
  describe "@derives on conditional_field (level 1, the outer)" do
    test "__fields__/0 carries derive on the conditional_field meta" do
      meta = find_field(D.OnConditionalField.__fields__(), :detail)
      assert meta.derive == "validate(map)"
      assert meta.__derive_ops__ == %{validate: [:map]}
    end

    test "runtime: decorator's validate(map) enforces BEFORE branch resolution" do
      # The string "not a map" is rejected by the conditional's own derive
      # before any branch is even tried — proves the decorator's payload
      # is actually applied at runtime, not just stored as metadata.
      assert {:error, _} = D.OnConditionalField.builder(%{detail: "not a map"})

      # Map inputs pass the validate(map), then the conditional resolves
      # to whichever branch's inner validator matches.
      assert {:ok, _} = D.OnConditionalField.builder(%{detail: %{tag: "x"}})
      assert {:ok, _} = D.OnConditionalField.builder(%{detail: %{tag: "x", extra: "y"}})
    end
  end

  # ============================================================
  # 6. @derives on a field INSIDE a sub_field body (level 2)
  # ============================================================
  describe "@derives on field inside sub_field (level 2)" do
    test "the AST walker recursed — inner field carries the derive" do
      meta = find_field(D.InsideSubField.Wrapper.__fields__(), :tag)
      assert meta.derive == "sanitize(trim) validate(string, max_len=5)"

      assert meta.__derive_ops__ == %{
               sanitize: [:trim],
               validate: [:string, {:max_len, 5}]
             }
    end

    test "runtime: inner max_len=5 enforced" do
      assert {:ok, _} = D.InsideSubField.builder(%{wrapper: %{tag: "x"}})

      assert {:error, _} =
               D.InsideSubField.builder(%{wrapper: %{tag: "way too long"}})
    end
  end

  # ============================================================
  # 7. @derives on field INSIDE a conditional_field branch
  # ============================================================
  describe "@derives on field inside conditional_field branch (level 2)" do
    test "branch-level field carries the derive payload" do
      # The conditional has 2 children; the FIELD branch has the @derives.
      [conditional] = D.InsideConditional.__fields__()
      assert conditional.kind == :conditional_field

      [string_branch | _] = conditional.children
      assert string_branch.derive == "validate(string, max_len=10)"
      assert string_branch.__derive_ops__ == %{validate: [:string, {:max_len, 10}]}
    end

    test "@derives also recurses into the sub_field branch's body" do
      meta = find_field(D.InsideConditional.Body1.__fields__(), :kind)
      assert meta.derive == "validate(string)"
      assert meta.__derive_ops__ == %{validate: [:string]}
    end

    test "runtime: each branch enforces its own decorator" do
      assert {:ok, _} = D.InsideConditional.builder(%{body: "ok"})

      assert {:error, _} =
               D.InsideConditional.builder(%{body: "this is too long for max_len=10"})

      assert {:ok, _} = D.InsideConditional.builder(%{body: %{kind: "anything"}})
    end
  end

  # ============================================================
  # 8. DEEP nesting — @derives at every depth (1 → 2 → 3 → 4)
  # ============================================================
  describe "deep nesting — @derives at levels 1, 2, 3, 4" do
    test "every level carries its own derive payload" do
      # Level 1 — top + sub_field meta
      top = find_field(D.DeepNested.__fields__(), :top)
      assert top.__derive_ops__ == %{validate: [:string, {:max_len, 10}]}

      l1_meta = find_field(D.DeepNested.__fields__(), :l1)
      assert l1_meta.__derive_ops__ == %{validate: [:map]}

      # Level 2 — inside l1's sub_field body
      l2_tag = find_field(D.DeepNested.L1.__fields__(), :tag)
      assert l2_tag.__derive_ops__ == %{validate: [:string, {:max_len, 20}]}

      # Level 3 — inside l2
      l3_tag = find_field(D.DeepNested.L1.L2.__fields__(), :tag)
      assert l3_tag.__derive_ops__ == %{validate: [:string, {:max_len, 30}]}

      # Level 4 — inside l3
      l4_tag = find_field(D.DeepNested.L1.L2.L3.__fields__(), :tag)
      assert l4_tag.__derive_ops__ == %{validate: [:string, {:max_len, 40}]}
    end

    test "runtime: every level's max_len rule is enforced independently" do
      # All-good build
      assert {:ok, _} =
               D.DeepNested.builder(%{
                 top: "topshort",
                 l1: %{
                   tag: "lvl2",
                   l2: %{
                     tag: "lvl3",
                     l3: %{tag: "lvl4"}
                   }
                 }
               })

      # Level 4 max_len=40 → 41-char tag fails
      assert {:error, _} =
               D.DeepNested.builder(%{
                 top: "ok",
                 l1: %{
                   tag: "ok",
                   l2: %{
                     tag: "ok",
                     l3: %{tag: String.duplicate("x", 41)}
                   }
                 }
               })

      # Level 1 max_len=10 fails at the top
      assert {:error, _} =
               D.DeepNested.builder(%{top: String.duplicate("x", 50)})
    end
  end

  # ============================================================
  # 9. Mixed-everything module — every entity type in one place
  # ============================================================
  describe "mixed all-entities module (every type, every level)" do
    test "__fields__/0 shows the right derive on each entity type" do
      fields = D.MixedAll.__fields__()

      assert find_field(fields, :plain).__derive_ops__ == %{validate: [:string]}
      assert find_field(fields, :extras).__derive_ops__ == %{validate: [:map]}
      assert find_field(fields, :totp).__derive_ops__ == %{validate: [:string, {:min_len, 3}]}
      assert find_field(fields, :nested).__derive_ops__ == %{validate: [:map]}
      # :variant intentionally has NO decorator on the conditional — see
      # the OnConditionalField fixture's docstring on why @derives there
      # blocks the string branch.
      assert find_field(fields, :variant).__derive_ops__ == nil
    end

    test "nested sub_field's submodule got its inner-field derive too" do
      meta = find_field(D.MixedAll.Nested.__fields__(), :label)
      assert meta.__derive_ops__ == %{validate: [:string, {:max_len, 10}]}
    end

    test "conditional_field's sub_field branch got its inner-field derive" do
      meta = find_field(D.MixedAll.Variant1.__fields__(), :value)
      assert meta.__derive_ops__ == %{validate: [:string]}
    end

    test "runtime: every layer's validation fires" do
      assert {:ok, _} =
               D.MixedAll.builder(%{
                 plain: "p",
                 extras: %{a: 1},
                 totp: "1234",
                 nested: %{label: "ok"},
                 variant: "string-variant"
               })

      # label max_len=10 fails
      assert {:error, _} =
               D.MixedAll.builder(%{
                 plain: "p",
                 totp: "1234",
                 nested: %{label: "way too long for the limit"}
               })

      # totp min_len=3 fails (this triggers main_validator)
      assert {:error, errs} =
               D.MixedAll.builder(%{plain: "p", totp: "xx"})

      errs = List.wrap(errs)
      assert Enum.any?(errs, &(&1[:field] == :totp))
    end
  end

  # ============================================================
  # 10. Coverage check — summary of decorator across all fixture modules
  # ============================================================
  describe "decorator coverage summary (one assertion proves every entity type was hit)" do
    test "every entity kind in the support file has a non-nil derive somewhere" do
      # If any future change breaks `@derives` for one entity type, the
      # matching coverage row will go nil and this test fails loudly.
      assert find_field(D.OnField.__fields__(), :name).derive != nil
      assert find_field(D.OnVirtualField.__fields__(), :password_confirmation).derive != nil
      assert find_field(D.OnDynamicField.__fields__(), :metadata).derive != nil
      assert find_field(D.OnSubField.__fields__(), :profile).derive != nil
      assert find_field(D.OnConditionalField.__fields__(), :detail).derive != nil
      assert find_field(D.InsideSubField.Wrapper.__fields__(), :tag).derive != nil
    end
  end
end
