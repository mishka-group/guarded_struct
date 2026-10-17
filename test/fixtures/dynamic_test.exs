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

  describe "dynamic_field below the top level" do
    # A dynamic_field keeps its keys exactly as sent wherever it is declared:
    # in a sub_field, in a sub_field of a sub_field, in a list sub_field, in a
    # struct: module, and in the sub_field branch of a conditional_field.

    @uuid "11111111-1111-1111-1111-111111111111"
    @meta %{
      "role" => "admin",
      :k => 1,
      "nested" => %{"deep" => %{"email" => 2}},
      "list" => [%{"inner" => 1}, %{"name" => 2}]
    }

    test "in a sub_field" do
      assert {:ok, envelope} =
               Dynamic.Envelope.builder(%{account: %{email: "a@b.c", meta: @meta}})

      assert envelope.account.meta == @meta
    end

    test "the same value at the top level and in a sub_field comes back the same" do
      assert {:ok, envelope} =
               Dynamic.Envelope.builder(%{top_meta: @meta, account: %{meta: @meta}})

      assert envelope.top_meta == envelope.account.meta
    end

    test "in a sub_field of a sub_field" do
      assert {:ok, envelope} =
               Dynamic.Envelope.builder(%{account: %{settings: %{theme: "dark", prefs: @meta}}})

      assert envelope.account.settings.prefs == @meta
    end

    test "in every item of a list sub_field" do
      other = %{"Other" => %{"role" => 1}}

      assert {:ok, envelope} =
               Dynamic.Envelope.builder(%{
                 events: [%{name: "a", payload: @meta}, %{name: "b", payload: other}]
               })

      assert [%{name: "a", payload: @meta}, %{name: "b", payload: ^other}] = envelope.events
    end

    test "in a struct: module" do
      assert {:ok, envelope} =
               Dynamic.Envelope.builder(%{
                 document: %{id: @uuid, body: "hi", metadata: @meta}
               })

      assert envelope.document.metadata == @meta
    end

    test "in the sub_field branch of a conditional_field" do
      assert {:ok, envelope} =
               Dynamic.Envelope.builder(%{attachment: %{kind: "file", data: @meta}})

      assert envelope.attachment.data == @meta
    end

    test "when the whole input is string-keyed" do
      assert {:ok, envelope} =
               Dynamic.Envelope.builder(%{
                 "top_meta" => @meta,
                 "account" => %{
                   "email" => "a@b.c",
                   "meta" => @meta,
                   "settings" => %{"theme" => "dark", "prefs" => @meta}
                 },
                 "events" => [%{"name" => "a", "payload" => @meta}]
               })

      assert envelope.top_meta == @meta
      assert envelope.account.email == "a@b.c"
      assert envelope.account.meta == @meta
      assert envelope.account.settings.theme == "dark"
      assert envelope.account.settings.prefs == @meta
      assert [%{name: "a", payload: @meta}] = envelope.events
    end

    test "attacker-controlled keys inside it do not create atoms" do
      key = "z9_nested_dynamic_neverdeclared_#{:rand.uniform(99_999_999)}"

      assert {:ok, envelope} =
               Dynamic.Envelope.builder(%{account: %{meta: %{key => 1, "x" => %{key => 2}}}})

      assert envelope.account.meta == %{key => 1, "x" => %{key => 2}}
      assert_raise ArgumentError, fn -> String.to_existing_atom(key) end
    end

    test "the declared fields around it are still converted" do
      assert {:ok, envelope} =
               Dynamic.Envelope.builder(%{
                 "account" => %{"email" => "a@b.c", "settings" => %{"theme" => "dark"}}
               })

      assert %Dynamic.Envelope.Account{
               email: "a@b.c",
               settings: %Dynamic.Envelope.Account.Settings{theme: "dark"}
             } = envelope.account
    end

    test "a plain map field of the same name elsewhere is still converted" do
      assert {:ok, envelope} =
               Dynamic.Envelope.builder(%{
                 "meta" => %{"email" => 1},
                 "account" => %{"meta" => %{"email" => 1}}
               })

      assert envelope.meta == %{email: 1}
      assert envelope.account.meta == %{"email" => 1}
    end

    test "the sub_field's own module keeps it when built on its own" do
      assert {:ok, account} = Dynamic.Envelope.Account.builder(%{"meta" => @meta})
      assert account.meta == @meta
    end

    test "an empty or missing one is the default" do
      assert {:ok, envelope} = Dynamic.Envelope.builder(%{account: %{email: "a@b.c"}})
      assert envelope.account.meta == %{}
    end

    test "GuardedStruct.Validate.partial/2 keeps the top-level and the nested ones" do
      assert {:ok, %{top_meta: @meta}} =
               GuardedStruct.Validate.partial(Dynamic.Envelope, %{"top_meta" => @meta})

      assert {:ok, %{account: %{meta: @meta}}} =
               GuardedStruct.Validate.partial(Dynamic.Envelope, %{
                 "account" => %{"meta" => @meta}
               })
    end
  end
end
