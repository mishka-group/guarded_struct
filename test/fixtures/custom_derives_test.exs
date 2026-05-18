defmodule GuardedStructFixtures.CustomDerivesTest do
  @moduledoc """
  Tests the `GuardedStructFixtures.CustomDerives` fixture — custom
  validators / sanitizers via `GuardedStruct.Derive.Extension`, wired
  through the `:derive_extensions` Application env.
  """

  # async: false — we mutate `Application.put_env(:guarded_struct, :derive_extensions, ...)`
  # which is process-global.
  use ExUnit.Case, async: false

  alias GuardedStructFixtures.CustomDerives

  setup do
    previous = Application.get_env(:guarded_struct, :derive_extensions, [])
    Application.put_env(:guarded_struct, :derive_extensions, [CustomDerives.MyDerives])
    on_exit(fn -> Application.put_env(:guarded_struct, :derive_extensions, previous) end)
    :ok
  end

  describe "slugify sanitizer + slug validator (composed custom ops)" do
    test "slugify transforms the input; slug validator passes" do
      # `:my_slug` has `derives: "sanitize(slugify) validate(slug)"`.
      # `slugify` (custom sanitizer) downcases + replaces non-alnum
      # with hyphens, then `slug` (custom validator) accepts the result.
      assert {:ok, art} =
               CustomDerives.Article.builder(%{
                 title: "Hello, World!",
                 my_slug: "Hello, World!"
               })

      assert art.my_slug == "hello-world"
    end

    test "slugify collapses runs of non-alphanumerics into single hyphens" do
      # Whitespace, punctuation, repeats — all become single hyphens.
      # Surrounding hyphens trimmed off the result.
      assert {:ok, art} =
               CustomDerives.Article.builder(%{
                 title: "x",
                 my_slug: "  Mishka --- Group !! 2026  "
               })

      assert art.my_slug == "mishka-group-2026"
    end

    test "slug validator rejects an empty/whitespace-only slug after slugify" do
      # ERROR REASON: slugify turns "!!!" into "" (all chars stripped),
      # then the `slug` validator (regex `^[a-z0-9][a-z0-9-]*$`) rejects
      # the empty string → :my_slug action error.
      assert {:error, errs} = CustomDerives.Article.builder(%{title: "x", my_slug: "!!!"})
      errs = List.wrap(errs)
      assert Enum.any?(errs, &(&1[:field] == :my_slug))
    end
  end

  describe "positive_int validator" do
    test "rejects 0 and negative values" do
      # ERROR REASON: custom `positive_int` validator requires `> 0`.
      # -1 fails → :positive_int action error on :views.
      assert {:error, errs} =
               CustomDerives.Article.builder(%{
                 title: "x",
                 my_slug: "x",
                 views: -1
               })

      errs = List.wrap(errs)
      assert Enum.any?(errs, &(&1[:field] == :views))
    end

    test "accepts positive integers" do
      # Sanity: 42 > 0 → validator passes.
      assert {:ok, %{views: 42}} =
               CustomDerives.Article.builder(%{
                 title: "x",
                 my_slug: "x",
                 views: 42
               })
    end

    test "defaults to 1 when omitted" do
      # `:views` has `default: 1`, which is > 0, so the validator
      # passes on the default.
      assert {:ok, %{views: 1}} =
               CustomDerives.Article.builder(%{title: "x", my_slug: "x"})
    end
  end
end
