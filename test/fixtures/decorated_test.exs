defmodule GuardedStructFixtures.DecoratedTest do
  @moduledoc """
  Tests the `GuardedStructFixtures.Decorated` fixture — `@derives` and
  `@derive_rules` decorators applied at top-level AND inside sub_field
  bodies (verifies the AST walker recurses).
  """

  use ExUnit.Case, async: true

  alias GuardedStructFixtures.Decorated

  describe "@derives / @derive_rules decorator on top-level fields" do
    test "decorated fields enforce the same rules as inline derives:" do
      assert {:ok, post} =
               Decorated.BlogPost.builder(%{
                 title: "  Hello  ",
                 body: "**markdown**",
                 slug: "hello-world"
               })

      assert post.title == "Hello"
    end

    test "rejects long titles via the @derives max_len rule" do
      assert {:error, errs} =
               Decorated.BlogPost.builder(%{
                 title: String.duplicate("x", 250),
                 body: "y"
               })

      assert Enum.any?(errs, &(&1[:field] == :title and &1[:action] == :max_len))
    end

    test "field without a decorator and without a derives: opt has no rule" do
      assert {:ok, %{draft: true}} =
               Decorated.BlogPost.builder(%{title: "ok", body: "ok", draft: true})

      assert {:ok, %{draft: false}} =
               Decorated.BlogPost.builder(%{title: "ok", body: "ok"})
    end

    test "@derive_rules (verbose alias) and @derives produce identical ops" do
      assert {:ok, post} =
               Decorated.BlogPost.builder(%{
                 title: "<script>alert('xss')</script>Hello",
                 body: "**bold**"
               })

      refute post.title =~ "<script"
    end
  end

  describe "@derives inside a sub_field body (AST walker recurses)" do
    test "decorated inner field's derives: validate(uuid) accepts a valid uuid" do
      uuid = "22222222-2222-2222-2222-222222222222"

      assert {:ok, post} =
               Decorated.BlogPost.builder(%{
                 title: "ok",
                 body: "ok",
                 metadata: %{tags: ["a", "b"], author_id: uuid}
               })

      assert post.metadata.author_id == uuid
    end

    test "rejects an invalid uuid on the decorated inner field" do
      assert {:error, _} =
               Decorated.BlogPost.builder(%{
                 title: "ok",
                 body: "ok",
                 metadata: %{author_id: "not-a-uuid"}
               })
    end
  end
end
