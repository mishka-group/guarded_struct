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

  describe "Post-compile introspection — derives per field via __fields__/0" do
    # After compile, each `guardedstruct` module exposes `__fields__/0`
    # returning a list of meta maps. For decorated fields, the same
    # post-resolution data lands there regardless of which form the user
    # wrote — `@derives "..."`, `@derive_rules "..."`, or inline `derives:`.
    # Each meta map carries:
    #   * `:derive`         — the raw op-string (post-resolution)
    #   * `:__derive_ops__` — the PARSED op-map (the runtime actually uses this)

    defp find_field(fields, name), do: Enum.find(fields, &(&1.name == name))

    test "BlogPost top-level fields carry the exact post-decorator derive info" do
      fields = Decorated.BlogPost.__fields__()

      # @derives "sanitize(strip_tags, trim) validate(string, not_empty, max_len=200)"
      title = find_field(fields, :title)
      assert title.derive ==
               "sanitize(strip_tags, trim) validate(string, not_empty, max_len=200)"

      assert title.__derive_ops__ == %{
               validate: [:string, :not_empty, {:max_len, 200}],
               sanitize: [:strip_tags, :trim]
             }

      # @derive_rules "sanitize(markdown_html, trim) validate(string, not_empty)"
      body = find_field(fields, :body)
      assert body.derive == "sanitize(markdown_html, trim) validate(string, not_empty)"

      assert body.__derive_ops__ == %{
               validate: [:string, :not_empty],
               sanitize: [:markdown_html, :trim]
             }

      # @derives "validate(string, max_len=50)"
      slug = find_field(fields, :slug)
      assert slug.derive == "validate(string, max_len=50)"
      assert slug.__derive_ops__ == %{validate: [:string, {:max_len, 50}]}

      # No decorator and no inline `derives:` → nil on both
      draft = find_field(fields, :draft)
      assert draft.derive == nil
      assert draft.__derive_ops__ == nil

      # @derives "validate(map)" on the sub_field itself
      metadata = find_field(fields, :metadata)
      assert metadata.derive == "validate(map)"
      assert metadata.__derive_ops__ == %{validate: [:map]}
    end

    test "BlogPost.Metadata sub_field's __fields__/0 shows decorator-injected derive inside the block" do
      # The decorator AST walker recurses into sub_field bodies, so the
      # `@derives "validate(uuid)"` written inside the `metadata` block
      # appears on `:author_id` in the submodule's __fields__/0.
      fields = Decorated.BlogPost.Metadata.__fields__()

      tags = find_field(fields, :tags)
      assert tags.derive == nil
      assert tags.__derive_ops__ == nil

      author_id = find_field(fields, :author_id)
      assert author_id.derive == "validate(uuid)"
      assert author_id.__derive_ops__ == %{validate: [:uuid]}
    end

    test "round-trip — every field that has a derive string also has parsed ops" do
      # Invariant: if `:derive` is a non-empty string, `:__derive_ops__`
      # must be a non-empty map. Catches accidental drift between the raw
      # op-string and its parsed form across the codegen pipeline.
      for f <- Decorated.BlogPost.__fields__() do
        case f.derive do
          nil ->
            assert f.__derive_ops__ == nil, "field #{inspect(f.name)} has nil derive but non-nil ops"

          "" ->
            assert f.__derive_ops__ == nil

          str when is_binary(str) ->
            assert is_map(f.__derive_ops__),
                   "field #{inspect(f.name)} has derive string #{inspect(str)} but no parsed ops"

            assert map_size(f.__derive_ops__) > 0,
                   "field #{inspect(f.name)} parsed to an EMPTY op map"
        end
      end
    end

    test "summary helper — name → derive op-string for every decorated field" do
      # This shape is what a user would build in iex/livebook to quickly
      # audit "what rule does each field actually enforce?".
      summary =
        Decorated.BlogPost.__fields__()
        |> Enum.map(fn f -> {f.name, f.derive} end)
        |> Enum.into(%{})

      assert summary == %{
               title: "sanitize(strip_tags, trim) validate(string, not_empty, max_len=200)",
               body: "sanitize(markdown_html, trim) validate(string, not_empty)",
               slug: "validate(string, max_len=50)",
               draft: nil,
               metadata: "validate(map)"
             }
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
