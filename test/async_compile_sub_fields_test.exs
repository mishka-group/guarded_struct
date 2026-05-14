defmodule GuardedStructTest.AsyncCompileSubFieldsTest do
  @moduledoc """
  Tests `GenerateSubFieldModules` use of `Spark.Dsl.Transformer.async_compile/2`
  for sub_field submodule compilation.
  """

  use ExUnit.Case, async: true

  alias GuardedStructTest.Fixtures.AsyncCompile.{
    SimpleParent,
    WideParent,
    DeepParent,
    WithConditional,
    OrderedDeep
  }

  describe "simple sub_field — flat submodule generation" do
    test "the Profile submodule exists and is fully compiled" do
      assert Code.ensure_loaded?(SimpleParent.Profile)
      assert function_exported?(SimpleParent.Profile, :builder, 1)
      assert function_exported?(SimpleParent.Profile, :keys, 0)
      assert function_exported?(SimpleParent.Profile, :__fields__, 0)
      assert function_exported?(SimpleParent.Profile, :__information__, 0)
      assert function_exported?(SimpleParent.Profile, :example, 0)
    end

    test "Profile.keys/0 reports the declared inner fields" do
      assert SimpleParent.Profile.keys() == [:nickname, :bio]
    end

    test "end-to-end build through SimpleParent works" do
      assert {:ok,
              %SimpleParent{
                id: "x",
                profile: %SimpleParent.Profile{nickname: "n", bio: "b"}
              }} =
               SimpleParent.builder(%{id: "x", profile: %{nickname: "n", bio: "b"}})
    end
  end

  describe "many sibling sub_fields — fan-out parallelism" do
    test "every sibling submodule compiles independently" do
      for letter <- [:A, :B, :C, :D] do
        mod = Module.concat(WideParent, letter)
        assert Code.ensure_loaded?(mod), "expected #{inspect(mod)} to exist"
        assert function_exported?(mod, :builder, 1)
      end
    end

    test "all four submodules are callable end-to-end" do
      assert {:ok, built} =
               WideParent.builder(%{
                 a: %{x: "1"},
                 b: %{x: "2"},
                 c: %{x: "3"},
                 d: %{x: "4"}
               })

      assert built.a.x == "1"
      assert built.b.x == "2"
      assert built.c.x == "3"
      assert built.d.x == "4"
    end
  end

  describe "deep nesting — parent → child → grandchild → great-grandchild" do
    test "every depth-level submodule exists and is callable" do
      mods = [
        DeepParent.Level1,
        DeepParent.Level1.Level2,
        DeepParent.Level1.Level2.Level3,
        DeepParent.Level1.Level2.Level3.Level4
      ]

      for mod <- mods do
        assert Code.ensure_loaded?(mod), "missing #{inspect(mod)}"
        assert function_exported?(mod, :builder, 1)
        assert function_exported?(mod, :keys, 0)
      end
    end

    test "end-to-end through all 4 levels of nesting" do
      input = %{
        level1: %{
          tag: "1",
          level2: %{
            tag: "2",
            level3: %{
              tag: "3",
              level4: %{value: "deep"}
            }
          }
        }
      }

      assert {:ok, built} = DeepParent.builder(input)
      assert built.level1.level2.level3.level4.value == "deep"
    end

    test "missing :value (enforced at the deepest level) propagates as an error" do
      input = %{
        level1: %{
          level2: %{
            level3: %{
              level4: %{}
            }
          }
        }
      }

      assert {:error, _} = DeepParent.builder(input)
    end
  end

  describe "conditional sub_fields — auto-numbered submodule names" do
    test "the auto-numbered Payload1 submodule exists" do
      assert Code.ensure_loaded?(WithConditional.Payload1)
      refute Code.ensure_loaded?(WithConditional.Payload)
    end

    test "the auto-numbered submodule has the inner field" do
      assert WithConditional.Payload1.keys() == [:kind]
    end

    test "end-to-end conditional resolves to either branch" do
      assert {:ok, %WithConditional{payload: "hello"}} =
               WithConditional.builder(%{payload: "hello"})

      assert {:ok, %WithConditional{payload: %WithConditional.Payload1{kind: "k"}}} =
               WithConditional.builder(%{payload: %{kind: "k"}})
    end
  end

  describe "async compile preserves ordering / dependency semantics" do
    test "parent's example/0 successfully calls child's example/0 (runtime resolution)" do
      ex = OrderedDeep.example()
      assert ex.nested.label == "child-default"
    end

    test "all expected submodules exist at the moment user code first runs" do
      assert Code.ensure_loaded?(OrderedDeep.Nested)
      assert function_exported?(OrderedDeep.Nested, :builder, 1)
      assert {:ok, _} = OrderedDeep.Nested.builder(%{})
    end
  end

  describe "regression: the full existing fixture set still passes end-to-end" do
    alias GuardedStructFixtures.{Conditionals, Decorated, Dynamic, Forms, Records, Showcase}

    test "Forms.Signup builds" do
      assert {:ok, _} =
               Forms.Signup.builder(%{
                 email: "x@y.io",
                 password: "longenough",
                 password_confirmation: "longenough"
               })
    end

    test "Decorated.BlogPost builds with the sub_field metadata" do
      uuid = "22222222-2222-2222-2222-222222222222"

      assert {:ok, _} =
               Decorated.BlogPost.builder(%{
                 title: "ok",
                 body: "ok",
                 metadata: %{tags: ["a"], author_id: uuid}
               })
    end

    test "Conditionals.Document — 7-level deep nesting still resolves" do
      input = %{
        title: "Hello",
        content: %{
          title: "Post",
          body: %{
            heading: "Section",
            paragraphs: [
              %{
                text: "quote",
                source: %{author: "Sh", url: "https://x.io"}
              }
            ]
          }
        }
      }

      assert {:ok, _} = Conditionals.Document.builder(input)
    end

    test "Dynamic.ClusterPlan composes pattern-keyed map" do
      assert {:ok, _} =
               Dynamic.ClusterPlan.builder(%{
                 status: "active",
                 shards: %{"shard_1" => %{node: "10.0.0.1"}}
               })
    end

    test "Records.UserEvent accepts a record" do
      require GuardedStructFixtures.Records
      rec = GuardedStructFixtures.Records.user(name: "A", age: 1)
      assert {:ok, _} = Records.UserEvent.builder(%{event_kind: :created, user: rec})
    end

    test "Showcase.EnterpriseAccount builds" do
      input = %{
        name: "Acme",
        owner: %{id: "44444444-4444-4444-4444-444444444444", email: "o@a.io"},
        members: [%{id: "55555555-5555-5555-5555-555555555555", email: "a@a.io"}],
        plan: "enterprise",
        settings: %{},
        invitation_token: "abcdefghij1234567890"
      }

      assert {:ok, _} = Showcase.EnterpriseAccount.builder(input)
    end
  end
end
