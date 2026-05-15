defmodule GuardedStructFixtures.DynamicTest do
  @moduledoc """
  Tests the `GuardedStructFixtures.Dynamic` fixture — `dynamic_field`
  (free-form map) and pattern-keyed map (regex `field` names), plus
  composing the two.
  """

  use ExUnit.Case, async: true

  alias GuardedStructFixtures.Dynamic

  describe "atom-attack safety (dynamic_field passthrough)" do
    # SECURITY: see SECURITY.md.
    # dynamic_field values are PASS-THROUGH — left entirely untouched
    # during input normalisation. No key conversion at any depth.
    # Whatever you submit, you get back — predictable, identity-preserving,
    # immune to atom-table-exhaustion DoS.

    @unique_prefix "z9_atomattack_neverdeclared_anywhere_"
    @uuid "11111111-1111-1111-1111-111111111111"

    test "dynamic_field value is identity-preserved — whatever you submit, you get back" do
      input = %{
        "foo" => 1,
        :bar => 2,
        "baz" => %{"nested" => 3},
        "list_of_maps" => [%{"inner" => 1}, %{"inner" => 2}]
      }

      {:ok, doc} =
        Dynamic.Document.builder(%{id: @uuid, body: "hi", metadata: input})

      # Byte-identical: NO key conversion at any depth.
      assert doc.metadata == input
    end

    test "attacker-controlled keys do NOT create new atoms" do
      key1 = @unique_prefix <> "aaa_#{:rand.uniform(99_999_999)}"
      key2 = @unique_prefix <> "bbb_#{:rand.uniform(99_999_999)}"

      {:ok, doc} =
        Dynamic.Document.builder(%{
          id: @uuid,
          body: "hi",
          metadata: %{key1 => 1, key2 => 2}
        })

      # Keys are still STRINGS — atomized versions DON'T exist:
      assert Map.has_key?(doc.metadata, key1)
      assert Map.has_key?(doc.metadata, key2)
      assert_raise ArgumentError, fn -> String.to_existing_atom(key1) end
      assert_raise ArgumentError, fn -> String.to_existing_atom(key2) end
    end

    test "declared FIELD-NAME keys (as strings) ARE still converted to atoms" do
      # The top-level field names are schema-declared atoms — submitting
      # them as strings still maps to the right atom (no atom growth, since
      # the atom already exists).
      assert {:ok, %Dynamic.Document{id: @uuid, body: "hi"}} =
               Dynamic.Document.builder(%{"id" => @uuid, "body" => "hi"})
    end

    test "even if a key inside metadata HAPPENS to match an existing atom, it stays a string" do
      # Predictability: previously `to_existing_atom` would opportunistically
      # convert "theme" if :theme atom existed elsewhere. With dynamic_field
      # passthrough, that no longer happens. dynamic_field values are
      # untouched, period.
      {:ok, doc} =
        Dynamic.Document.builder(%{
          id: @uuid,
          body: "hi",
          metadata: %{"id" => "user-supplied-string", "name" => "x"}
        })

      # :id atom exists (it's a declared field name), but inside the
      # dynamic_field VALUE, "id" stays as a string. No magic.
      assert doc.metadata == %{"id" => "user-supplied-string", "name" => "x"}
      refute Map.has_key?(doc.metadata, :id)
    end
  end

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
