defmodule GuardedStructFixtures.MixedDecoratorInlineTest do
  @moduledoc """
  Tests that the `@derives` decorator and inline `derives:` opt can be
  freely mixed in the same module / nested module, AND that both forms
  produce identical `__derive_ops__` metadata.
  """

  use ExUnit.Case, async: true

  alias GuardedStructFixtures.MixedDecoratorInline, as: M

  defp find_field(fields, name), do: Enum.find(fields, &(&1.name == name))

  describe "siblings — decorator on field A, inline on field B" do
    test "both forms produce parsed op maps in __fields__/0" do
      fields = M.SiblingMix.__fields__()

      assert find_field(fields, :short_name).__derive_ops__ ==
               %{validate: [:string, {:max_len, 5}]}

      assert find_field(fields, :long_name).__derive_ops__ ==
               %{validate: [:string, {:max_len, 50}]}
    end

    test "runtime: each field enforces its own rule independently" do
      assert {:ok, _} = M.SiblingMix.builder(%{short_name: "ok", long_name: "still fine"})

      # short_name max_len=5 fails
      assert {:error, _} =
               M.SiblingMix.builder(%{short_name: "way too long", long_name: "ok"})

      # long_name max_len=50 fails
      assert {:error, _} =
               M.SiblingMix.builder(%{
                 short_name: "ok",
                 long_name: String.duplicate("x", 60)
               })
    end
  end

  describe "outer decorator + inner inline" do
    test "decorator on the sub_field meta, inline on the inner field" do
      outer = find_field(M.OuterDecoratorInnerInline.__fields__(), :profile)
      assert outer.__derive_ops__ == %{validate: [:map]}

      inner = find_field(M.OuterDecoratorInnerInline.Profile.__fields__(), :nickname)
      assert inner.__derive_ops__ == %{validate: [:string, {:max_len, 20}]}
    end

    test "runtime: both rules enforce" do
      assert {:ok, _} =
               M.OuterDecoratorInnerInline.builder(%{profile: %{nickname: "ok"}})

      # outer validate(map) fails
      assert {:error, _} =
               M.OuterDecoratorInnerInline.builder(%{profile: "not a map"})

      # inner max_len=20 fails
      assert {:error, _} =
               M.OuterDecoratorInnerInline.builder(%{
                 profile: %{nickname: String.duplicate("x", 30)}
               })
    end
  end

  describe "outer inline + inner decorator" do
    test "inline on the sub_field meta, decorator on the inner field" do
      outer = find_field(M.OuterInlineInnerDecorator.__fields__(), :profile)
      assert outer.__derive_ops__ == %{validate: [:map]}

      inner = find_field(M.OuterInlineInnerDecorator.Profile.__fields__(), :nickname)
      assert inner.__derive_ops__ == %{validate: [:string, {:max_len, 20}]}
    end

    test "runtime: both rules enforce (mirror of the previous case)" do
      assert {:ok, _} =
               M.OuterInlineInnerDecorator.builder(%{profile: %{nickname: "ok"}})

      assert {:error, _} =
               M.OuterInlineInnerDecorator.builder(%{profile: "not a map"})

      assert {:error, _} =
               M.OuterInlineInnerDecorator.builder(%{
                 profile: %{nickname: String.duplicate("x", 30)}
               })
    end
  end

  describe "both forms on the SAME field — inline wins (precedence rule)" do
    test "the inline derives: max_len=100 wins, not the decorator's max_len=5" do
      meta = find_field(M.BothOnSameField.__fields__(), :name)
      # max_len=100 (inline) is in the parsed ops, NOT max_len=5 (decorator)
      assert meta.__derive_ops__ == %{validate: [:string, {:max_len, 100}]}
    end

    test "runtime: a 50-char name passes (would fail the decorator's max_len=5)" do
      # The decorator-only rule would reject this; inline (max_len=100) accepts.
      assert {:ok, _} =
               M.BothOnSameField.builder(%{name: String.duplicate("x", 50)})

      # But 150 chars still fails the inline max_len=100
      assert {:error, _} =
               M.BothOnSameField.builder(%{name: String.duplicate("x", 150)})
    end
  end

  describe "adjacent virtual_field — one decorator, one inline" do
    test "each virtual carries its own derive ops" do
      fields = M.VirtualMix.__fields__()

      assert find_field(fields, :totp_a).__derive_ops__ ==
               %{validate: [:string, {:min_len, 4}]}

      assert find_field(fields, :totp_b).__derive_ops__ ==
               %{validate: [:string, {:min_len, 6}]}
    end

    test "runtime: both virtual_field derives enforce independently" do
      assert {:ok, _} =
               M.VirtualMix.builder(%{keep: "x", totp_a: "abcd", totp_b: "abcdef"})

      # totp_a min_len=4 fails (3 chars)
      assert {:error, errs} =
               M.VirtualMix.builder(%{keep: "x", totp_a: "abc", totp_b: "abcdef"})

      errs = List.wrap(errs)
      assert Enum.any?(errs, &(&1[:field] == :totp_a and &1[:action] == :min_len))

      # totp_b min_len=6 fails (5 chars)
      assert {:error, errs} =
               M.VirtualMix.builder(%{keep: "x", totp_a: "abcd", totp_b: "short"})

      errs = List.wrap(errs)
      assert Enum.any?(errs, &(&1[:field] == :totp_b and &1[:action] == :min_len))
    end

    test "decorator is one-shot — it does NOT leak past totp_a to totp_b" do
      # If the decorator leaked, totp_b would have min_len=4 (totp_a's rule).
      # We verify by sending a 5-char value to totp_b: should FAIL with
      # totp_b's own min_len=6 rule (and message), not totp_a's.
      assert {:error, errs} =
               M.VirtualMix.builder(%{keep: "x", totp_a: "abcd", totp_b: "abcde"})

      errs = List.wrap(errs)
      # The failure is on totp_b — proving its OWN derive is enforced, not
      # leaked-from-decorator.
      assert Enum.any?(errs, &(&1[:field] == :totp_b))
    end
  end

  describe "decorator on conditional + inline on branch field" do
    test "both forms coexist in a conditional structure" do
      cond_meta = find_field(M.ConditionalMix.__fields__(), :detail)
      assert cond_meta.__derive_ops__ == %{validate: [:map]}

      tag_meta = find_field(M.ConditionalMix.Detail1.__fields__(), :tag)
      assert tag_meta.__derive_ops__ == %{validate: [:string, {:max_len, 8}]}
    end

    test "runtime: conditional's validate(map) blocks non-maps; tag's max_len=8 enforces" do
      assert {:ok, _} =
               M.ConditionalMix.builder(%{detail: %{tag: "okok"}})

      assert {:error, _} =
               M.ConditionalMix.builder(%{detail: "not a map"})

      assert {:error, _} =
               M.ConditionalMix.builder(%{detail: %{tag: "way too long"}})
    end
  end
end
