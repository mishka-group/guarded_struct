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
      # `@derives` above `:title` injects the same sanitize/validate ops
      # as if written inline. Sanitize trims the leading/trailing spaces.
      assert {:ok, post} =
               Decorated.BlogPost.builder(%{
                 title: "  Hello  ",
                 body: "**markdown**",
                 slug: "hello-world"
               })

      assert post.title == "Hello"
    end

    test "rejects long titles via the @derives max_len rule" do
      # ERROR REASON: the @derives line above `:title` includes
      # `max_len=200`. 250 x's exceed it → :max_len action error.
      assert {:error, errs} =
               Decorated.BlogPost.builder(%{
                 title: String.duplicate("x", 250),
                 body: "y"
               })

      assert Enum.any?(errs, &(&1[:field] == :title and &1[:action] == :max_len))
    end

    test "field without a decorator and without a derives: opt has no rule" do
      # `:draft` is declared with neither a decorator nor inline `derives:`
      # → any value passes (here: true / default false). Confirms decorator
      # is one-shot — it doesn't leak to the next field.
      assert {:ok, %{draft: true}} =
               Decorated.BlogPost.builder(%{title: "ok", body: "ok", draft: true})

      assert {:ok, %{draft: false}} =
               Decorated.BlogPost.builder(%{title: "ok", body: "ok"})
    end

    test "@derive_rules (verbose alias) and @derives produce identical ops" do
      # `@derive_rules` decorates `:body` with `sanitize(markdown_html)`
      # which strips dangerous HTML. `<script>` tags must not survive.
      assert {:ok, post} =
               Decorated.BlogPost.builder(%{
                 title: "<script>alert('xss')</script>Hello",
                 body: "**bold**"
               })

      refute post.title =~ "<script"
    end
  end

  describe "Full struct equality (deep map comparison)" do
    test "BlogPost.builder/1 returns the EXACT %BlogPost{} struct, every key & nested sub_field asserted at once" do
      uuid = "22222222-2222-2222-2222-222222222222"

      assert Decorated.BlogPost.builder(%{
               title: "  Hello  ",
               body: "**bold**",
               slug: "hello-world",
               draft: true,
               metadata: %{tags: ["a", "b"], author_id: uuid}
             }) ==
               {:ok,
                %Decorated.BlogPost{
                  title: "Hello",
                  body: "**bold**",
                  slug: "hello-world",
                  draft: true,
                  metadata: %Decorated.BlogPost.Metadata{
                    tags: ["a", "b"],
                    author_id: uuid
                  }
                }}
    end

    test "BlogPost.builder/1 with only enforce'd fields → all optional fields take their defaults" do
      assert Decorated.BlogPost.builder(%{title: "x", body: "y"}) ==
               {:ok,
                %Decorated.BlogPost{
                  title: "x",
                  body: "y",
                  slug: nil,
                  draft: false,
                  metadata: nil
                }}
    end
  end

  describe "@derives inside a sub_field body (AST walker recurses)" do
    test "decorated inner field's derives: validate(uuid) accepts a valid uuid" do
      # The walker recurses into the `:metadata` sub_field body, so
      # `@derives "validate(uuid)"` above `:author_id` applies even
      # though it's two levels deep, not at the outermost block.
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
      # ERROR REASON: same nested `@derives "validate(uuid)"` rule
      # applies. "not-a-uuid" doesn't match the uuid shape → :uuid
      # action error on `metadata.author_id`.
      assert {:error, _} =
               Decorated.BlogPost.builder(%{
                 title: "ok",
                 body: "ok",
                 metadata: %{author_id: "not-a-uuid"}
               })
    end
  end
end
