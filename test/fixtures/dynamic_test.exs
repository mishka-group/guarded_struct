defmodule GuardedStructFixtures.DynamicTest do
  @moduledoc """
  Tests the `GuardedStructFixtures.Dynamic` fixture — `dynamic_field`
  (free-form map) and pattern-keyed map (regex `field` names), plus
  composing the two.
  """

  use ExUnit.Case, async: true

  alias GuardedStructFixtures.Dynamic

  describe "dynamic_field — free-form map" do
    test "defaults to %{}" do
      assert {:ok, doc} =
               Dynamic.Document.builder(%{
                 id: "33333333-3333-3333-3333-333333333333",
                 body: "hi"
               })

      assert doc.metadata == %{}
    end

    test "accepts any map shape at runtime" do
      assert {:ok, doc} =
               Dynamic.Document.builder(%{
                 id: "33333333-3333-3333-3333-333333333333",
                 body: "hi",
                 metadata: %{author: "x", tags: ["a"]}
               })

      assert doc.metadata.author == "x"
    end

    test "rejects non-map metadata via the implicit validate(map) derive" do
      assert {:error, _} =
               Dynamic.Document.builder(%{
                 id: "33333333-3333-3333-3333-333333333333",
                 body: "hi",
                 metadata: "not a map"
               })
    end

    test "rejects non-uuid id on the parent" do
      assert {:error, _} =
               Dynamic.Document.builder(%{id: "not-uuid", body: "hi"})
    end
  end

  describe "Pattern-keyed map (regex field name)" do
    test "builds a plain map of validated structs" do
      assert {:ok, %{"shard_1" => %Dynamic.Shard{node: "10.0.0.1"}}} =
               Dynamic.ShardsMap.builder(%{"shard_1" => %{node: "10.0.0.1"}})
    end

    test "rejects keys that don't match the regex" do
      assert {:error, _} =
               Dynamic.ShardsMap.builder(%{"banana" => %{node: "10.0.0.1"}})
    end

    test "rejects an empty input via validate(map, not_empty)" do
      assert {:error, _} = Dynamic.ShardsMap.builder(%{})
    end

    test "rejects non-IPv4 node strings inside Shard" do
      assert {:error, _} =
               Dynamic.ShardsMap.builder(%{"shard_1" => %{node: "not-an-ip"}})
    end

    test "Shard.replicas defaults to 1" do
      assert {:ok, %{"shard_1" => %Dynamic.Shard{replicas: 1}}} =
               Dynamic.ShardsMap.builder(%{"shard_1" => %{node: "10.0.0.1"}})
    end
  end

  describe "Composing a pattern-keyed map module via struct:" do
    test "ClusterPlan validates the status enum AND the inner ShardsMap" do
      assert {:ok, plan} =
               Dynamic.ClusterPlan.builder(%{
                 status: "active",
                 shards: %{"shard_1" => %{node: "10.0.0.1"}}
               })

      assert plan.status == "active"
      assert match?(%{"shard_1" => %Dynamic.Shard{}}, plan.shards)
    end

    test "ClusterPlan rejects an invalid status" do
      assert {:error, _} =
               Dynamic.ClusterPlan.builder(%{
                 status: "unknown",
                 shards: %{"shard_1" => %{node: "10.0.0.1"}}
               })
    end
  end
end
