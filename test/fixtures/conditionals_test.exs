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
end
