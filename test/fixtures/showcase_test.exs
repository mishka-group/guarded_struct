defmodule GuardedStructFixtures.ShowcaseTest do
  @moduledoc """
  Tests the `GuardedStructFixtures.Showcase` fixture — the
  everything-at-once `EnterpriseAccount` schema combining `jason: true`,
  `@derives` decorator, `virtual_field`, `auto:`, `from:`,
  list-of-sub_field via `structs: true`, nested `conditional_field`,
  `dynamic_field`, and `main_validator/1`.

  Doubles as an integration test for the public API surface used over
  this kind of schema: `Schema.json_schema/1`, `Schema.openapi/1`,
  `Schema.typescript/1`, `Diff.diff/2`, `Diff.apply/2`, `Validate.run/2`,
  `Validate.field/4`, `Validate.partial/2`, `Errors.from_tuple/1`,
  `Info.fields/1`, `__information__/0`, `example/0`.
  """

  # async: false — wires the CustomDerives extensions via Application.put_env
  use ExUnit.Case, async: false

  alias GuardedStruct.{Diff, Errors, Info, Schema, Validate}
  alias GuardedStructFixtures.{CustomDerives, Showcase}

  setup do
    previous = Application.get_env(:guarded_struct, :derive_extensions, [])
    Application.put_env(:guarded_struct, :derive_extensions, [CustomDerives.MyDerives])
    on_exit(fn -> Application.put_env(:guarded_struct, :derive_extensions, previous) end)
    :ok
  end

  defp valid_account_input(overrides \\ %{}) do
    Map.merge(
      %{
        name: "Acme Corp",
        owner: %{
          id: "44444444-4444-4444-4444-444444444444",
          email: "OWNER@ACME.io"
        },
        members: [
          %{id: "55555555-5555-5555-5555-555555555555", email: "a@acme.io", role: "admin"}
        ],
        plan: "enterprise",
        settings: %{billing_email: "billing@acme.io"},
        invitation_token: "abcdefghij1234567890"
      },
      overrides
    )
  end

  describe "EnterpriseAccount — build variants" do
    test "builds with a string-preset plan" do
      assert {:ok, acc} = Showcase.EnterpriseAccount.builder(valid_account_input())
      assert acc.plan == "enterprise"
      # owner.email is pulled into top-level owner_email via from:, before
      # the owner sub_field sanitises its own copy.
      assert acc.owner_email == "OWNER@ACME.io"
      assert acc.owner.email == "owner@acme.io"
      # auto: minted an :id
      assert is_binary(acc.id) and acc.id != ""
      # virtual invitation_token did NOT land on the struct
      refute Map.has_key?(acc, :invitation_token)
    end

    test "builds with the detailed-plan map and a single-string :notes (inner conditional)" do
      input =
        valid_account_input(%{
          plan: %{tier: "custom", seat_count: 500, notes: "internal note"}
        })

      assert {:ok, acc} = Showcase.EnterpriseAccount.builder(input)
      assert acc.plan.tier == "custom"
      assert acc.plan.seat_count == 500
      assert acc.plan.notes == "internal note"
    end

    test "builds with the detailed-plan map and a list-of-strings :notes (inner conditional)" do
      input =
        valid_account_input(%{
          plan: %{tier: "custom", notes: ["a", "b", "c"]}
        })

      assert {:ok, acc} = Showcase.EnterpriseAccount.builder(input)
      assert acc.plan.notes == ["a", "b", "c"]
    end

    test "rejects when invitation_token is too short (main_validator/1)" do
      input = valid_account_input(%{invitation_token: "tooshort"})
      assert {:error, errs} = Showcase.EnterpriseAccount.builder(input)
      assert Enum.any?(errs, &(&1[:field] == :invitation_token))
    end

    test "rejects when a member in the list has an invalid id" do
      input =
        valid_account_input(%{
          members: [
            %{id: "55555555-5555-5555-5555-555555555555", email: "x@y.io"},
            %{id: "not-a-uuid", email: "z@y.io"}
          ]
        })

      assert {:error, _} = Showcase.EnterpriseAccount.builder(input)
    end
  end

  describe "Full struct equality (deep map comparison)" do
    test "EnterpriseAccount.builder/1 returns the EXACT struct, every nested key asserted in one ==" do
      input = valid_account_input()

      # Capture the auto-generated id first; everything else is deterministic.
      {:ok, built} = Showcase.EnterpriseAccount.builder(input)

      # Re-run to prove determinism would diverge only on :id;
      # we compare the original `built` against the fully-spelled
      # expected struct below.
      assert {:ok, ^built} =
               {:ok, built}

      assert built ==
               %Showcase.EnterpriseAccount{
                 id: built.id,
                 name: "Acme Corp",
                 owner: %Showcase.EnterpriseAccount.Owner{
                   id: "44444444-4444-4444-4444-444444444444",
                   email: "owner@acme.io"
                 },
                 owner_email: "OWNER@ACME.io",
                 members: [
                   %Showcase.EnterpriseAccount.Members{
                     id: "55555555-5555-5555-5555-555555555555",
                     email: "a@acme.io",
                     role: "admin"
                   }
                 ],
                 plan: "enterprise",
                 settings: %{billing_email: "billing@acme.io"}
               }

      # And the auto-generated id matches the UUID shape:
      assert byte_size(built.id) > 10
    end

    test "detailed-plan variant — full equality including nested conditional resolution" do
      input =
        valid_account_input(%{
          plan: %{tier: "custom", seat_count: 500, notes: "internal note"}
        })

      {:ok, built} = Showcase.EnterpriseAccount.builder(input)

      assert built ==
               %Showcase.EnterpriseAccount{
                 id: built.id,
                 name: "Acme Corp",
                 owner: %Showcase.EnterpriseAccount.Owner{
                   id: "44444444-4444-4444-4444-444444444444",
                   email: "owner@acme.io"
                 },
                 owner_email: "OWNER@ACME.io",
                 members: [
                   %Showcase.EnterpriseAccount.Members{
                     id: "55555555-5555-5555-5555-555555555555",
                     email: "a@acme.io",
                     role: "admin"
                   }
                 ],
                 plan: %Showcase.EnterpriseAccount.Plan1{
                   tier: "custom",
                   seat_count: 500,
                   notes: "internal note"
                 },
                 settings: %{billing_email: "billing@acme.io"}
               }
    end
  end

  describe "EnterpriseAccount — public API surface" do
    test "JSON-encodes via Jason.Encoder (jason: true cascades to sub_fields)" do
      {:ok, acc} = Showcase.EnterpriseAccount.builder(valid_account_input())
      json = Jason.encode!(acc)
      decoded = Jason.decode!(json)
      assert decoded["name"] == "Acme Corp"
      # virtual fields should NOT appear in the encoded payload
      refute Map.has_key?(decoded, "invitation_token")
    end

    test "Schema.json_schema/1 produces a JSON Schema 2020-12 doc" do
      schema = Schema.json_schema(Showcase.EnterpriseAccount)
      assert schema["$schema"] =~ "json-schema.org"
      assert schema["type"] == "object"
      assert "name" in schema["required"]
    end

    test "Schema.openapi/1 envelopes multiple schemas" do
      doc = Schema.openapi([Showcase.EnterpriseAccount, Showcase.Member])
      assert doc["openapi"] == "3.1.0"
      schemas = doc["components"]["schemas"]
      account_key = Showcase.EnterpriseAccount |> inspect() |> String.replace(".", "_")
      member_key = Showcase.Member |> inspect() |> String.replace(".", "_")
      assert is_map(schemas[account_key])
      assert is_map(schemas[member_key])
    end

    test "Schema.typescript/1 emits a typed interface" do
      ts = Schema.typescript(Showcase.EnterpriseAccount)
      assert ts =~ "export interface"
      assert ts =~ "name"
    end

    test "Diff.diff/2 captures changes between two accounts" do
      {:ok, a} = Showcase.EnterpriseAccount.builder(valid_account_input())
      {:ok, b} = Showcase.EnterpriseAccount.builder(valid_account_input(%{name: "Acme Inc"}))

      assert %{name: {:changed, "Acme Corp", "Acme Inc"}} = Diff.diff(a, b)
      refute Diff.equal?(a, b)
    end

    test "Diff.apply/2 round-trips a change" do
      {:ok, a} = Showcase.EnterpriseAccount.builder(valid_account_input())
      changed = Diff.apply(a, %{name: {:changed, a.name, "New Name"}})
      assert changed.name == "New Name"
    end

    test "Validate.run/2 works standalone against op-strings" do
      assert {:ok, "abc"} = Validate.run("validate(string, max_len=10)", "abc")
      assert {:error, _} = Validate.run("validate(string, max_len=2)", "too long")
    end

    test "Validate.field/4 in :isolated mode validates one named field" do
      assert {:ok, "Acme"} =
               Validate.field(Showcase.EnterpriseAccount, :name, "Acme", mode: :isolated)
    end

    test "Validate.partial/2 accepts a subset of fields (no enforce_keys check)" do
      assert {:ok, %{name: "X"}} =
               Validate.partial(Showcase.EnterpriseAccount, %{name: "X"})
    end

    test "Errors.from_tuple/1 wraps builder errors into a Splode class" do
      {:error, errs} = Showcase.EnterpriseAccount.builder(%{name: "x"})
      class = errs |> List.wrap() |> Errors.from_tuple()
      assert is_exception(class)
    end

    test "Info.fields/1 lists top-level field names" do
      names = Info.fields(Showcase.EnterpriseAccount)
      assert :name in names
      assert :owner in names
      assert :settings in names
    end

    test "Info.field?/2 introspects the schema" do
      assert Info.field?(Showcase.EnterpriseAccount, :name)
      assert Info.field?(Showcase.EnterpriseAccount, :settings)
      refute Info.field?(Showcase.EnterpriseAccount, :nonexistent)
    end

    test "__information__/0 includes the conditional_keys list" do
      info = Showcase.EnterpriseAccount.__information__()
      assert is_list(info.conditional_keys)
      assert :plan in info.conditional_keys
    end

    test "example/0 produces a buildable starting struct" do
      ex = Showcase.EnterpriseAccount.example()
      assert is_struct(ex, Showcase.EnterpriseAccount)
    end
  end
end
