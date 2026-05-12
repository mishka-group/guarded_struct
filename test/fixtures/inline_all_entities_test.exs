defmodule GuardedStructFixtures.InlineAllEntitiesTest do
  @moduledoc """
  End-to-end tests for inline `derives:` opt on every entity type.

  Mirrors `DecoratedAllEntitiesTest` — both syntactic forms should
  produce identical `__derive_ops__` metadata AND identical runtime
  enforcement.

  Critical regression lock: the `OnVirtualField` runtime test confirms
  `derives:` on `virtual_field` ACTUALLY fires (previously broken before
  the two-pass derive fix in Runtime).
  """

  use ExUnit.Case, async: true

  alias GuardedStructFixtures.InlineAllEntities, as: I

  defp find_field(fields, name), do: Enum.find(fields, &(&1.name == name))

  describe "inline derives: on field (level 1)" do
    test "__fields__/0 carries the parsed sanitize+validate op map" do
      # Inline `derives:` lands in `__fields__/0` exactly the same as the
      # decorator form would — same parsed op map.
      meta = find_field(I.OnField.__fields__(), :name)
      assert meta.derive == "sanitize(trim) validate(string, max_len=10)"
      assert meta.__derive_ops__ == %{sanitize: [:trim], validate: [:string, {:max_len, 10}]}
    end

    test "runtime: sanitize trims input, max_len=10 rejects long input" do
      # "  x  " → sanitize(trim) → "x" → validate(string, max_len=10) passes.
      assert {:ok, %{name: "x"}} = I.OnField.builder(%{name: "  x  "})

      # ERROR REASON: 16-char "this is too long" exceeds max_len=10 → :max_len.
      assert {:error, _} = I.OnField.builder(%{name: "this is too long"})
    end
  end

  describe "inline derives: on virtual_field (level 1)" do
    test "__fields__/0 includes the virtual_field with its derive ops" do
      # Even though virtual_field is dropped from the struct, its derive
      # ops live in __fields__/0 for introspection (and runtime, see below).
      meta = find_field(I.OnVirtualField.__fields__(), :password_confirmation)
      assert meta.derive == "validate(string, min_len=8)"
      assert meta.__derive_ops__ == %{validate: [:string, {:min_len, 8}]}
    end

    test "runtime (FIXED): min_len=8 actually fires on the virtual value" do
      # Pre-fix: this would have succeeded because virtual_field derives
      # were dropped before run_derives/2. Now the two-pass derive in
      # Runtime catches them on the merged map before wrap drops them.

      # Happy path: 10-char password passes min_len=8.
      assert {:ok, struct} =
               I.OnVirtualField.builder(%{keep: "x", password_confirmation: "longenough"})

      refute Map.has_key?(struct, :password_confirmation)

      # ERROR REASON: "short" (5 chars) fails min_len=8 → :min_len error.
      assert {:error, errs} =
               I.OnVirtualField.builder(%{keep: "x", password_confirmation: "short"})

      assert Enum.any?(
               errs,
               &(&1[:field] == :password_confirmation and &1[:action] == :min_len)
             )
    end
  end

  describe "inline derives: on dynamic_field (level 1)" do
    test "inline derives wins over the schema default `validate(map)`" do
      # dynamic_field's schema-default `derives:` is `"validate(map)"`. The
      # user's explicit `derives:` opt replaces it — `__derive_ops__` reflects
      # the user's choice, not the default.
      meta = find_field(I.OnDynamicField.__fields__(), :metadata)
      assert meta.derive == "validate(map, not_empty)"
      assert meta.__derive_ops__ == %{validate: [:map, :not_empty]}
    end

    test "runtime: not_empty rejects the default empty map" do
      # ERROR REASON: dynamic_field's `default: %{}` is applied when input
      # omits :metadata. The user's `validate(map, not_empty)` then runs
      # against `%{}` and the :not_empty check fails.
      assert {:error, _} = I.OnDynamicField.builder(%{})

      # Non-empty map passes both :map and :not_empty.
      assert {:ok, _} = I.OnDynamicField.builder(%{metadata: %{any: "value"}})
    end
  end

  describe "inline derives: on sub_field (level 1)" do
    test "__fields__/0 carries derive on the sub_field meta" do
      # The derive is on the OUTER meta (the sub_field declaration itself),
      # not on the inner submodule. So __fields__/0 of the parent shows it.
      meta = find_field(I.OnSubField.__fields__(), :profile)
      assert meta.derive == "validate(map)"
      assert meta.__derive_ops__ == %{validate: [:map]}
    end

    test "runtime: non-map rejected before descending into sub_field body" do
      # ERROR REASON: sub_field's `derives: "validate(map)"` runs on the
      # sub_field's input value BEFORE descending into the body — a string
      # fails the :map check and the body never runs.
      assert {:error, _} = I.OnSubField.builder(%{profile: "not a map"})

      # Map passes :map → body descends → inner field accepts any string.
      assert {:ok, _} = I.OnSubField.builder(%{profile: %{bio: "hello"}})
    end
  end

  describe "inline derives: on conditional_field (level 1)" do
    test "__fields__/0 carries derive on the conditional_field meta" do
      meta = find_field(I.OnConditionalField.__fields__(), :detail)
      assert meta.derive == "validate(map)"
      assert meta.__derive_ops__ == %{validate: [:map]}
    end

    test "runtime: pre-branch validate(map) blocks non-map inputs" do
      # ERROR REASON: conditional_field's derive runs BEFORE branch
      # resolution. validate(map) on the conditional itself means the
      # value MUST be a map — string is rejected here, not at branch.
      assert {:error, _} = I.OnConditionalField.builder(%{detail: "not a map"})

      # Maps pass the pre-branch :map check, then branch resolution picks
      # whichever sub_field branch's `validator:` matches (both branches
      # are :is_map here so the first matches; second works the same way).
      assert {:ok, _} = I.OnConditionalField.builder(%{detail: %{tag: "x"}})
      assert {:ok, _} = I.OnConditionalField.builder(%{detail: %{tag: "x", extra: "y"}})
    end
  end

  describe "inline derives: on field INSIDE a sub_field body (level 2)" do
    test "inner field carries the derive in submodule __fields__/0" do
      # The derive is on the INNER field of a sub_field. The auto-generated
      # submodule (Wrapper) has its own __fields__/0 that exposes this.
      meta = find_field(I.InsideSubField.Wrapper.__fields__(), :tag)
      assert meta.derive == "sanitize(trim) validate(string, max_len=5)"

      assert meta.__derive_ops__ == %{
               sanitize: [:trim],
               validate: [:string, {:max_len, 5}]
             }
    end

    test "runtime: inner max_len=5 enforced" do
      # "x" passes (after trim) the max_len=5 check.
      assert {:ok, _} = I.InsideSubField.builder(%{wrapper: %{tag: "x"}})

      # ERROR REASON: "way too long" is 12 chars > max_len=5 → :max_len.
      assert {:error, _} =
               I.InsideSubField.builder(%{wrapper: %{tag: "way too long"}})
    end
  end

  describe "inline derives: on conditional branch fields" do
    test "branch field's __derive_ops__ is populated" do
      # Each branch of a conditional has its own derive ops in `children`.
      [conditional] = I.InsideConditional.__fields__()
      assert conditional.kind == :conditional_field

      [string_branch | _] = conditional.children
      assert string_branch.derive == "validate(string, max_len=10)"
      assert string_branch.__derive_ops__ == %{validate: [:string, {:max_len, 10}]}
    end

    test "inner sub_field branch field also carries its derive" do
      # The conditional's SECOND branch is a sub_field — `Body1` is the
      # auto-numbered submodule. Its inner :kind field's derive lives in
      # the submodule's __fields__/0.
      meta = find_field(I.InsideConditional.Body1.__fields__(), :kind)
      assert meta.derive == "validate(string)"
      assert meta.__derive_ops__ == %{validate: [:string]}
    end

    test "runtime: each branch enforces independently" do
      # String branch's max_len=10 passes for "ok" (2 chars).
      assert {:ok, _} = I.InsideConditional.builder(%{body: "ok"})

      # ERROR REASON: string branch's max_len=10 rejects this 32-char input.
      assert {:error, _} =
               I.InsideConditional.builder(%{body: "this is too long for max_len=10"})

      # Map input goes to the sub_field branch where :kind's derive(string)
      # accepts any binary.
      assert {:ok, _} = I.InsideConditional.builder(%{body: %{kind: "anything"}})
    end
  end

  describe "deep nesting — inline derives: at levels 1, 2, 3, 4" do
    test "every level carries its own derive payload" do
      # Inline derives at four different depths land in four different
      # submodules' __fields__/0 — each with the right max_len limit.
      top = find_field(I.DeepNested.__fields__(), :top)
      assert top.__derive_ops__ == %{validate: [:string, {:max_len, 10}]}

      l1 = find_field(I.DeepNested.__fields__(), :l1)
      assert l1.__derive_ops__ == %{validate: [:map]}

      l2_tag = find_field(I.DeepNested.L1.__fields__(), :tag)
      assert l2_tag.__derive_ops__ == %{validate: [:string, {:max_len, 20}]}

      l3_tag = find_field(I.DeepNested.L1.L2.__fields__(), :tag)
      assert l3_tag.__derive_ops__ == %{validate: [:string, {:max_len, 30}]}

      l4_tag = find_field(I.DeepNested.L1.L2.L3.__fields__(), :tag)
      assert l4_tag.__derive_ops__ == %{validate: [:string, {:max_len, 40}]}
    end

    test "runtime: every level's max_len rule is enforced" do
      # Every level's tag fits its level's max_len → all pass.
      assert {:ok, _} =
               I.DeepNested.builder(%{
                 top: "topshort",
                 l1: %{
                   tag: "lvl2",
                   l2: %{tag: "lvl3", l3: %{tag: "lvl4"}}
                 }
               })

      # ERROR REASON: level-4's tag is 41 chars > max_len=40 → error
      # bubbles up through level 3 → 2 → 1 → root.
      assert {:error, _} =
               I.DeepNested.builder(%{
                 top: "ok",
                 l1: %{
                   tag: "ok",
                   l2: %{tag: "ok", l3: %{tag: String.duplicate("x", 41)}}
                 }
               })

      # ERROR REASON: 50-char :top exceeds level-1 max_len=10. Top-level
      # fails immediately without needing the nested children.
      assert {:error, _} =
               I.DeepNested.builder(%{top: String.duplicate("x", 50)})
    end
  end

  describe "mixed all-entities module (inline form)" do
    test "__fields__/0 shows the right derive on each entity type" do
      # Lock that every entity-type's inline derive lands correctly.
      # If any entity-type's inline support breaks, exactly one of these
      # assertions will fail.
      fields = I.MixedAll.__fields__()

      assert find_field(fields, :plain).__derive_ops__ == %{validate: [:string]}
      assert find_field(fields, :extras).__derive_ops__ == %{validate: [:map]}
      assert find_field(fields, :totp).__derive_ops__ == %{validate: [:string, {:min_len, 3}]}
      assert find_field(fields, :nested).__derive_ops__ == %{validate: [:map]}
    end

    test "nested sub_field's submodule has its inner-field derive" do
      # Inner-field derives live on the auto-generated submodule, not
      # on the parent. Confirms the codegen plumbs them into the right
      # __fields__/0.
      meta = find_field(I.MixedAll.Nested.__fields__(), :label)
      assert meta.__derive_ops__ == %{validate: [:string, {:max_len, 10}]}
    end

    test "runtime: every layer's validation fires" do
      # Happy path — every layer's derive passes.
      assert {:ok, _} =
               I.MixedAll.builder(%{
                 plain: "p",
                 extras: %{a: 1},
                 totp: "1234",
                 nested: %{label: "ok"},
                 variant: "string-variant"
               })

      # ERROR REASON: :label's max_len=10 (inside the sub_field's submodule)
      # rejects the long label. Error bubbles up from the submodule.
      assert {:error, _} =
               I.MixedAll.builder(%{
                 plain: "p",
                 totp: "1234",
                 nested: %{label: "way too long for the limit"},
                 variant: "x"
               })

      # ERROR REASON: :totp is a VIRTUAL field with min_len=3. "xx" (2
      # chars) fails. This test specifically locks in the virtual_field
      # runtime fix — pre-fix it would NOT have rejected this input.
      assert {:error, errs} =
               I.MixedAll.builder(%{plain: "p", totp: "xx", variant: "x"})

      errs = List.wrap(errs)

      assert Enum.any?(
               errs,
               &(&1[:field] == :totp and &1[:action] == :min_len)
             )
    end
  end
end
