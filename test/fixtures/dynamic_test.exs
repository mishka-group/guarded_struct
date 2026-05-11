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
      # `dynamic_field :metadata` declares `default: %{}` under the hood
      # → omitting it yields the empty map.
      assert {:ok, doc} =
               Dynamic.Document.builder(%{
                 id: "33333333-3333-3333-3333-333333333333",
                 body: "hi"
               })

      assert doc.metadata == %{}
    end

    test "accepts any map shape at runtime" do
      # Free-form keys/values — no compile-time schema for inner shape.
      # The implicit `validate(map)` is the only constraint.
      assert {:ok, doc} =
               Dynamic.Document.builder(%{
                 id: "33333333-3333-3333-3333-333333333333",
                 body: "hi",
                 metadata: %{author: "x", tags: ["a"]}
               })

      assert doc.metadata.author == "x"
    end

    test "rejects non-map metadata via the implicit validate(map) derive" do
      # ERROR REASON: `dynamic_field` carries `derives: "validate(map)"`
      # by default. A plain string fails the :map check.
      assert {:error, _} =
               Dynamic.Document.builder(%{
                 id: "33333333-3333-3333-3333-333333333333",
                 body: "hi",
                 metadata: "not a map"
               })
    end

    test "rejects non-uuid id on the parent" do
      # ERROR REASON: `:id` has `derives: "validate(uuid)"`. The string
      # "not-uuid" doesn't match the uuid pattern → :uuid action error.
      assert {:error, _} =
               Dynamic.Document.builder(%{id: "not-uuid", body: "hi"})
    end
  end

  describe "Pattern-keyed map (regex field name)" do
    test "builds a plain map of validated structs" do
      # Regex `field` name → the module's builder/1 returns a PLAIN MAP
      # (no defstruct), keyed by the input string keys, with each value
      # built through the referenced `Shard` module.
      assert {:ok, %{"shard_1" => %Dynamic.Shard{node: "10.0.0.1"}}} =
               Dynamic.ShardsMap.builder(%{"shard_1" => %{node: "10.0.0.1"}})
    end

    test "rejects keys that don't match the regex" do
      # ERROR REASON: declared regex is `~r/^shard_\d+$/`. "banana"
      # doesn't match → key rejected by the pattern-map runtime.
      assert {:error, _} =
               Dynamic.ShardsMap.builder(%{"banana" => %{node: "10.0.0.1"}})
    end

    test "rejects an empty input via validate(map, not_empty)" do
      # ERROR REASON: the regex field's `derives:` includes `not_empty`.
      # An empty input map fails the :not_empty check.
      assert {:error, _} = Dynamic.ShardsMap.builder(%{})
    end

    test "rejects non-IPv4 node strings inside Shard" do
      # ERROR REASON: `Shard.node` has `derives: "validate(ipv4)"`.
      # "not-an-ip" is not a valid IPv4 address.
      assert {:error, _} =
               Dynamic.ShardsMap.builder(%{"shard_1" => %{node: "not-an-ip"}})
    end

    test "Shard.replicas defaults to 1" do
      # `Shard.replicas` has `default: 1`. Omitting it yields 1, not nil.
      assert {:ok, %{"shard_1" => %Dynamic.Shard{replicas: 1}}} =
               Dynamic.ShardsMap.builder(%{"shard_1" => %{node: "10.0.0.1"}})
    end
  end

  describe "Composing a pattern-keyed map module via struct:" do
    test "ClusterPlan validates the status enum AND the inner ShardsMap" do
      # `:status` enum-validates, `:shards` delegates to ShardsMap
      # which pattern-key-validates each entry — both pipelines run.
      assert {:ok, plan} =
               Dynamic.ClusterPlan.builder(%{
                 status: "active",
                 shards: %{"shard_1" => %{node: "10.0.0.1"}}
               })

      assert plan.status == "active"
      assert match?(%{"shard_1" => %Dynamic.Shard{}}, plan.shards)
    end

    test "ClusterPlan rejects an invalid status" do
      # ERROR REASON: `:status` derives include
      # `enum=String[draft::active::archived]`. "unknown" is not in the
      # allowed set → :enum action error.
      assert {:error, _} =
               Dynamic.ClusterPlan.builder(%{
                 status: "unknown",
                 shards: %{"shard_1" => %{node: "10.0.0.1"}}
               })
    end
  end
end
