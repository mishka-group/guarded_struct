defmodule GuardedStructFixtures.ConditionalsTest do
  @moduledoc """
  Tests the `GuardedStructFixtures.Conditionals` fixture — covering
  nested `conditional_field` resolution (the headline 0.1.0 unblocker).
  """

  use ExUnit.Case, async: true

  alias GuardedStructFixtures.Conditionals

  describe "Block (nested conditional_field)" do
    test "resolves a plain paragraph (string) to the first branch" do
      assert {:ok, %Conditionals.Block{block: "hello world"}} =
               Conditionals.Block.builder(%{block: "hello world"})
    end

    test "resolves a single image (map) to the sub_field branch" do
      assert {:ok, %Conditionals.Block{block: %{url: url}}} =
               Conditionals.Block.builder(%{block: %{url: "https://x.io/a.png"}})

      assert url == "https://x.io/a.png"
    end

    test "resolves a gallery (list) to the INNER conditional with list children" do
      gallery = [
        "https://x.io/cap.png",
        %{url: "https://x.io/img.png", alt: "a pic"}
      ]

      assert {:ok, %Conditionals.Block{block: items}} =
               Conditionals.Block.builder(%{block: gallery})

      assert length(items) == 2
    end

    test "rejects a value that matches no branch (number)" do
      assert {:error, _} = Conditionals.Block.builder(%{block: 42})
    end

    test "gallery item with an invalid URL inside a map fails the inner url validator" do
      gallery = [%{url: "not-a-url"}]
      assert {:error, _} = Conditionals.Block.builder(%{block: gallery})
    end

    test "single image map with a non-url url fails the url validator" do
      assert {:error, _} = Conditionals.Block.builder(%{block: %{url: "ftp://broken"}})
    end
  end

  # ------------------------------------------------------------------
  # Comprehensive shape — calling Block.builder/1 and showing the FULL
  # data returned for each variant, plus introspection on the parent
  # module and the auto-generated submodule.
  # ------------------------------------------------------------------
  describe "Block.builder/1 — full result shape and introspection" do
    test "parent Block module surface: keys/0, enforce_keys/0, __information__/0" do
      # The user-facing shape of the top-level module has exactly ONE field
      # `:block`, which is itself a conditional_field with 3 variants.
      assert Conditionals.Block.keys() == [:block]
      assert Conditionals.Block.enforce_keys() == []

      info = Conditionals.Block.__information__()
      assert info.module == Conditionals.Block
      assert info.keys == [:block]
      assert info.enforce_keys == []
      assert info.conditional_keys == [:block]
      assert info.path == []
      assert info.key == :root
      assert info.options == %{jason: false, authorized_fields: false}
    end

    test "__fields__/0 exposes the FULL conditional shape — all 3 variants" do
      [%{name: :block, kind: :conditional_field, children: children}] =
        Conditionals.Block.__fields__()

      # Three variants, in declaration order:
      [string_variant, image_variant, gallery_variant] = children

      # 1. Paragraph — leaf string field with a derive
      assert string_variant.name == :block
      assert string_variant.kind == :field
      assert string_variant.hint == "paragraph"
      assert string_variant.derive == "validate(string, max_len=10_000)"
      assert string_variant.__derive_ops__ == %{validate: [:string, {:max_len, 10_000}]}
      assert string_variant.validator == {Conditionals.Validators, :is_string}

      # 2. Single image — sub_field that generates its own submodule
      assert image_variant.name == :block
      assert image_variant.kind == :sub_field
      assert image_variant.hint == "image"
      assert image_variant.validator == {Conditionals.Validators, :is_map}
      assert image_variant.sub_field_index == 1
      refute image_variant.list?

      # 3. Gallery — list-of-conditional, each item is its own conditional
      assert gallery_variant.name == :block
      assert gallery_variant.kind == :conditional_field
      assert gallery_variant.hint == "gallery"
      assert gallery_variant.validator == {Conditionals.Validators, :is_list}
      assert gallery_variant.list? == true

      [item_string, item_image] = gallery_variant.children
      assert item_string.hint == "gallery_item_string"
      assert item_string.derive == "validate(string, max_len=2048)"
      assert item_image.hint == "gallery_item_image"
      # External-struct reference (no submodule generated; delegates to Image)
      assert item_image.struct == Conditionals.Image
    end

    test "paragraph variant: full %Block{} result with every key visible" do
      assert {:ok, result} = Conditionals.Block.builder(%{block: "hello"})

      # Exactly one key on the parent struct, populated with the string.
      assert result == %Conditionals.Block{block: "hello"}
      assert result |> Map.keys() |> Enum.sort() == [:__struct__, :block]
    end

    test "image variant: result.block is a fully-typed %Block.Block1{} submodule" do
      assert {:ok, result} =
               Conditionals.Block.builder(%{block: %{url: "https://x.io/a.png"}})

      # The conditional resolves to the sub_field branch, which generated
      # the submodule `Block.Block1` (the first sub_field child of the
      # outer conditional).
      assert %Conditionals.Block{block: image} = result
      assert is_struct(image, Conditionals.Block.Block1)

      # Submodule has its own keys/enforce/example surface
      assert Conditionals.Block.Block1.keys() == [:url, :alt]
      assert Conditionals.Block.Block1.enforce_keys() == [:url]
      assert is_struct(Conditionals.Block.Block1.example(), Conditionals.Block.Block1)

      # Provided URL surfaced; :alt populated with its default "".
      assert image.url == "https://x.io/a.png"
      assert image.alt == ""

      # Submodule fully exposes its keys including __struct__
      assert Map.keys(image) |> Enum.sort() == [:__struct__, :alt, :url]
    end

    test "image variant: an explicit :alt value flows through" do
      assert {:ok, %Conditionals.Block{block: image}} =
               Conditionals.Block.builder(%{
                 block: %{url: "https://x.io/cat.png", alt: "a cat"}
               })

      assert image.alt == "a cat"
    end

    test "gallery variant: result.block is a list where each item is fully resolved" do
      assert {:ok, %Conditionals.Block{block: items}} =
               Conditionals.Block.builder(%{
                 block: [
                   "https://x.io/header.png",
                   %{url: "https://x.io/img1.png"},
                   %{url: "https://x.io/img2.png", alt: "second"}
                 ]
               })

      assert length(items) == 3
      [first, second, third] = items

      # First is the string variant (resolved by the inner conditional)
      assert first == "https://x.io/header.png"

      # Second/third are %Image{} structs (external struct ref → delegates
      # to GuardedStructFixtures.Conditionals.Image.builder/1)
      assert is_struct(second, Conditionals.Image)
      assert second.url == "https://x.io/img1.png"
      assert second.alt == ""

      assert is_struct(third, Conditionals.Image)
      assert third.alt == "second"
    end

    test "Image (the external struct referenced by gallery items) has its own surface" do
      assert Conditionals.Image.keys() == [:url, :alt]
      assert Conditionals.Image.enforce_keys() == [:url]

      info = Conditionals.Image.__information__()
      assert info.module == Conditionals.Image
      assert info.enforce_keys == [:url]
      assert info.conditional_keys == []
    end

    test "Block.example/0 produces a complete starter struct" do
      ex = Conditionals.Block.example()
      assert is_struct(ex, Conditionals.Block)
      # Top-level keys present:
      assert Map.has_key?(ex, :block)
    end
  end

  # ------------------------------------------------------------------
  # Full deep-map equality — assert the ENTIRE returned struct in one
  # `==` so any drift in any nested key fails the test loudly.
  # ------------------------------------------------------------------
  describe "Full struct equality (deep map comparison)" do
    test "paragraph variant — Block.builder/1 returns the EXACT %Block{} in one assert" do
      assert Conditionals.Block.builder(%{block: "hello world"}) ==
               {:ok, %Conditionals.Block{block: "hello world"}}
    end

    test "image variant — Block.builder/1 returns Block with nested %Block1{} struct, every key set" do
      assert Conditionals.Block.builder(%{
               block: %{url: "https://x.io/a.png", alt: "alt text"}
             }) ==
               {:ok,
                %Conditionals.Block{
                  block: %Conditionals.Block.Block1{
                    url: "https://x.io/a.png",
                    alt: "alt text"
                  }
                }}
    end

    test "image variant — :alt defaults to \"\" when omitted (full equality with default applied)" do
      assert Conditionals.Block.builder(%{block: %{url: "https://x.io/a.png"}}) ==
               {:ok,
                %Conditionals.Block{
                  block: %Conditionals.Block.Block1{
                    url: "https://x.io/a.png",
                    alt: ""
                  }
                }}
    end

    test "gallery variant — Block.builder/1 returns full list of resolved Image structs + strings" do
      assert Conditionals.Block.builder(%{
               block: [
                 "https://x.io/header.png",
                 %{url: "https://x.io/img1.png"},
                 %{url: "https://x.io/img2.png", alt: "second"}
               ]
             }) ==
               {:ok,
                %Conditionals.Block{
                  block: [
                    "https://x.io/header.png",
                    %Conditionals.Image{url: "https://x.io/img1.png", alt: ""},
                    %Conditionals.Image{url: "https://x.io/img2.png", alt: "second"}
                  ]
                }}
    end
  end
end
