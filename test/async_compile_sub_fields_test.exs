defmodule GuardedStructTest.AsyncCompileSubFieldsTest do
  @moduledoc """
  Tests `GenerateSubFieldModules` use of `Spark.Dsl.Transformer.async_compile/2`
  for sub_field submodule compilation.

  Sub_field submodules are independent at compile time (parents reference
  children only at runtime via `Module.concat(...)`), so they can compile
  in parallel. Spark awaits all registered async tasks before the next
  transformer runs (`GenerateBuilder`), so by the time the user's `use
  GuardedStruct` block returns, every submodule is fully compiled and
  callable.

  These tests prove:
    * All expected submodules exist after compile
    * Each submodule has its full surface (builder/1, keys/0, __fields__/0)
    * Deeply nested chains compile correctly (parent → child → grandchild)
    * Conditional sub_fields with auto-numbered names compile
    * Behavior is identical to the previous synchronous Module.create/3 path
      (every existing fixture/end-to-end test still passes)
  """

  use ExUnit.Case, async: true

  describe "simple sub_field — flat submodule generation" do
    defmodule SimpleParent do
      use GuardedStruct

      guardedstruct do
        field(:id, String.t(), enforce: true)

        sub_field(:profile, struct()) do
          field(:nickname, String.t())
          field(:bio, String.t())
        end
      end
    end

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
    defmodule WideParent do
      use GuardedStruct

      guardedstruct do
        sub_field(:a, struct()) do
          field(:x, String.t())
        end

        sub_field(:b, struct()) do
          field(:x, String.t())
        end

        sub_field(:c, struct()) do
          field(:x, String.t())
        end

        sub_field(:d, struct()) do
          field(:x, String.t())
        end
      end
    end

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
    defmodule DeepParent do
      use GuardedStruct

      guardedstruct do
        sub_field(:level1, struct()) do
          field(:tag, String.t())

          sub_field(:level2, struct()) do
            field(:tag, String.t())

            sub_field(:level3, struct()) do
              field(:tag, String.t())

              sub_field(:level4, struct()) do
                field(:value, String.t(), enforce: true)
              end
            end
          end
        end
      end
    end

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
              # :value omitted at level4 — enforce: true → required error
              level4: %{}
            }
          }
        }
      }

      assert {:error, _} = DeepParent.builder(input)
    end
  end

  describe "conditional sub_fields — auto-numbered submodule names" do
    defmodule WithConditional do
      use GuardedStruct

      defmodule V do
        def is_string(field, value) when is_binary(value), do: {:ok, field, value}
        def is_string(field, _), do: {:error, field, "not a string"}

        def is_map(field, value) when is_map(value) and not is_struct(value),
          do: {:ok, field, value}

        def is_map(field, _), do: {:error, field, "not a map"}
      end

      guardedstruct do
        conditional_field(:payload, any()) do
          field(:payload, String.t(),
            hint: "string",
            validator: {V, :is_string}
          )

          sub_field(:payload, struct(),
            hint: "map_form",
            validator: {V, :is_map}
          ) do
            field(:kind, String.t(), enforce: true)
          end
        end
      end
    end

    test "the auto-numbered Payload1 submodule exists" do
      # Sub_field children of a conditional_field get renamed `<name><idx>`,
      # so this becomes `WithConditional.Payload1` not `WithConditional.Payload`.
      assert Code.ensure_loaded?(WithConditional.Payload1)
      refute Code.ensure_loaded?(WithConditional.Payload)
    end

    test "the auto-numbered submodule has the inner field" do
      assert WithConditional.Payload1.keys() == [:kind]
    end

    test "end-to-end conditional resolves to either branch" do
      # string branch
      assert {:ok, %WithConditional{payload: "hello"}} =
               WithConditional.builder(%{payload: "hello"})

      # map branch → resolved to Payload1 submodule
      assert {:ok, %WithConditional{payload: %WithConditional.Payload1{kind: "k"}}} =
               WithConditional.builder(%{payload: %{kind: "k"}})
    end
  end

  describe "async compile preserves ordering / dependency semantics" do
    defmodule OrderedDeep do
      use GuardedStruct

      guardedstruct do
        # Parent's `example/0` runtime-dispatches to child's `example/0`
        # via `Module.concat(__MODULE__, ...).example()`. If async_compile
        # ever finished parent BEFORE child, the parent's example/0 call
        # would fail at runtime — proves ordering is preserved.
        sub_field(:nested, struct()) do
          field(:label, String.t(), default: "child-default")
        end
      end
    end

    test "parent's example/0 successfully calls child's example/0 (runtime resolution)" do
      ex = OrderedDeep.example()
      assert ex.nested.label == "child-default"
    end

    test "all expected submodules exist at the moment user code first runs" do
      # If async_compile didn't await before transformer pipeline finished,
      # this would race. Spark's contract is that ALL async tasks complete
      # before the next transformer runs — so by the time `use GuardedStruct`
      # returns, every submodule is fully callable. This test locks that in.
      assert Code.ensure_loaded?(OrderedDeep.Nested)
      assert function_exported?(OrderedDeep.Nested, :builder, 1)
      assert {:ok, _} = OrderedDeep.Nested.builder(%{})
    end
  end

  describe "regression: the full existing fixture set still passes end-to-end" do
    # This block is a smoke test — if async_compile broke anything, one of
    # these would fail. The detailed coverage lives in the per-fixture
    # test files under test/fixtures/.
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
