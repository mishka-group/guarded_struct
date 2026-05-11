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
      assert {:ok, art} =
               CustomDerives.Article.builder(%{
                 title: "Hello, World!",
                 slug: "Hello, World!"
               })

      assert art.slug == "hello-world"
    end

    test "slugify collapses runs of non-alphanumerics into single hyphens" do
      assert {:ok, art} =
               CustomDerives.Article.builder(%{
                 title: "x",
                 slug: "  Mishka --- Group !! 2026  "
               })

      assert art.slug == "mishka-group-2026"
    end

    test "slug validator rejects an empty/whitespace-only slug after slugify" do
      assert {:error, errs} = CustomDerives.Article.builder(%{title: "x", slug: "!!!"})
      errs = List.wrap(errs)
      assert Enum.any?(errs, &(&1[:field] == :slug))
    end
  end

  describe "positive_int validator" do
    test "rejects 0 and negative values" do
      assert {:error, errs} =
               CustomDerives.Article.builder(%{
                 title: "x",
                 slug: "x",
                 views: -1
               })

      errs = List.wrap(errs)
      assert Enum.any?(errs, &(&1[:field] == :views))
    end

    test "accepts positive integers" do
      assert {:ok, %{views: 42}} =
               CustomDerives.Article.builder(%{
                 title: "x",
                 slug: "x",
                 views: 42
               })
    end

    test "defaults to 1 when omitted" do
      assert {:ok, %{views: 1}} =
               CustomDerives.Article.builder(%{title: "x", slug: "x"})
    end
  end
end
