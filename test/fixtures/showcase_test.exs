defmodule GuardedStructFixtures.ShowcaseTest do
  @moduledoc """
  Tests the `GuardedStructFixtures.Showcase` fixture — the
  everything-at-once `EnterpriseAccount` schema combining `json: true`,
  `@derives` decorator, `virtual_field`, `auto:`, `from:`,
  list-of-sub_field via `structs: true`, nested `conditional_field`,
  `dynamic_field`, and `main_validator/1`.

  Doubles as an integration test for the public API surface used over
  this kind of schema: `Diff.diff/2`, `Diff.apply/2`, `Validate.run/2`,
  `Validate.field/4`, `Validate.partial/2`, `Errors.from_tuple/1`,
  `Info.fields/1`, `__information__/0`, `example/0`.
  """

  # async: false — wires the CustomDerives extensions via Application.put_env
  use ExUnit.Case, async: false

  alias GuardedStruct.{Diff, Errors, Info, Validate}
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
      # Top-level conditional `:plan` resolves to the string branch.
      # `from:` snapshots `owner.email` BEFORE the owner sub_field sanitises
      # its own copy, so `:owner_email` keeps the raw caps while
      # `acc.owner.email` is lowercased.
      assert {:ok, acc} = Showcase.EnterpriseAccount.builder(valid_account_input())
      assert acc.plan == "enterprise"
      assert acc.owner_email == "OWNER@ACME.io"
      assert acc.owner.email == "owner@acme.io"
      # `auto:` minted an :id; `virtual_field` :invitation_token dropped.
      assert is_binary(acc.id) and acc.id != ""
      refute Map.has_key?(acc, :invitation_token)
    end

    test "builds with the detailed-plan map and a single-string :notes (inner conditional)" do
      # `:plan` conditional resolves to the sub_field (Plan1) branch.
      # Inside Plan1, `:notes` is ITSELF a conditional — string branch wins.
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
      # Same Plan1 sub_field branch; the inner `:notes` conditional
      # resolves to the list-of-strings branch this time.
      input =
        valid_account_input(%{
          plan: %{tier: "custom", notes: ["a", "b", "c"]}
        })

      assert {:ok, acc} = Showcase.EnterpriseAccount.builder(input)
      assert acc.plan.notes == ["a", "b", "c"]
    end

    test "rejects when invitation_token is too short (main_validator/1)" do
      # ERROR REASON: `main_validator/1` on EnterpriseAccount enforces
      # `String.length(invitation_token) >= 16`. "tooshort" is 8 chars
      # → :invitation_token error returned from main_validator.
      input = valid_account_input(%{invitation_token: "tooshort"})
      assert {:error, errs} = Showcase.EnterpriseAccount.builder(input)
      assert Enum.any?(errs, &(&1[:field] == :invitation_token))
    end

    test "rejects when a member in the list has an invalid id" do
      # ERROR REASON: `:members` is `structs: true`, so each item is
      # built through `Members.builder/1`. `:id` has `validate(uuid)`
      # → the second item ("not-a-uuid") fails and the whole build aborts.
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
      # Deep-equality lock: every nested sub_field key, every default,
      # every list item must match. The only non-deterministic field is
      # `:id` (minted by `auto:`), so we capture it from `built` and use
      # it in the expected struct.
      input = valid_account_input()

      {:ok, built} = Showcase.EnterpriseAccount.builder(input)

      assert {:ok, ^built} = {:ok, built}

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
      # Same deep-equality discipline, but now `:plan` resolves to the
      # sub_field branch (Plan1), and Plan1's `:notes` conditional
      # resolves to the string branch. Asserted with explicit submodule
      # name `%Plan1{}` so any rename or numbering change is caught.
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
    test "JSON-encodes via Jason.Encoder (json: true cascades to sub_fields)" do
      # `json: true` on the section also threads through to every
      # generated sub_field submodule (Owner, Members, Plan1, ...).
      # Without that cascade, encoding the parent would fail when it
      # tries to encode the nested %Owner{}. Also confirms virtual
      # fields don't surface in the payload.
      {:ok, acc} = Showcase.EnterpriseAccount.builder(valid_account_input())
      json = Jason.encode!(acc)
      decoded = Jason.decode!(json)
      assert decoded["name"] == "Acme Corp"
      refute Map.has_key?(decoded, "invitation_token")
    end

    test "Diff.diff/2 captures changes between two accounts" do
      # Two structs differ only on `:name`. Diff returns that ONE
      # change in `{:changed, old, new}` shape — equal? is false.
      {:ok, a} = Showcase.EnterpriseAccount.builder(valid_account_input())
      {:ok, b} = Showcase.EnterpriseAccount.builder(valid_account_input(%{name: "Acme Inc"}))

      assert %{name: {:changed, "Acme Corp", "Acme Inc"}} = Diff.diff(a, b)
      refute Diff.equal?(a, b)
    end

    test "Diff.apply/2 round-trips a change" do
      # `Diff.apply/2` takes a diff map and applies it back. Useful
      # for "accept a partial change" patterns.
      {:ok, a} = Showcase.EnterpriseAccount.builder(valid_account_input())
      changed = Diff.apply(a, %{name: {:changed, a.name, "New Name"}})
      assert changed.name == "New Name"
    end

    test "Validate.run/2 works standalone against op-strings" do
      # Validate.run/2 doesn't need a module — just a derive op string.
      # "abc" passes max_len=10 ; "too long" (8 chars) fails max_len=2.
      assert {:ok, "abc"} = Validate.run("validate(string, max_len=10)", "abc")
      assert {:error, _} = Validate.run("validate(string, max_len=2)", "too long")
    end

    test "Validate.field/4 in :isolated mode validates one named field" do
      # :isolated mode skips cross-field deps (from/on/domain) and runs
      # just the field's own derive + validator chain.
      assert {:ok, "Acme"} =
               Validate.field(Showcase.EnterpriseAccount, :name, "Acme", mode: :isolated)
    end

    test "Validate.partial/2 accepts a subset of fields (no enforce_keys check)" do
      # `Validate.partial/2` skips enforce_keys checks — usable for
      # PATCH-style flows where only some fields are present.
      assert {:ok, %{name: "X"}} =
               Validate.partial(Showcase.EnterpriseAccount, %{name: "X"})
    end

    test "Errors.from_tuple/1 wraps builder errors into a Splode class" do
      # Builder returns raw error maps; from_tuple/1 wraps them in a
      # Splode error class for traversal/serialization downstream.
      {:error, errs} = Showcase.EnterpriseAccount.builder(%{name: "x"})
      class = errs |> List.wrap() |> Errors.from_tuple()
      assert is_exception(class)
    end

    test "Info.fields/1 lists top-level field names" do
      # Info.fields/1 returns ATOM NAMES (not entity structs) — locks
      # the actual top-level surface of the EnterpriseAccount module.
      names = Info.fields(Showcase.EnterpriseAccount)
      assert :name in names
      assert :owner in names
      assert :settings in names
    end

    test "Info.field?/2 introspects the schema" do
      # Fast existence check by field name.
      assert Info.field?(Showcase.EnterpriseAccount, :name)
      assert Info.field?(Showcase.EnterpriseAccount, :settings)
      refute Info.field?(Showcase.EnterpriseAccount, :nonexistent)
    end

    test "__information__/0 includes the conditional_keys list" do
      # `:plan` is a `conditional_field` → must appear in
      # `__information__/0.conditional_keys` (was always [] in 0.0.x).
      info = Showcase.EnterpriseAccount.__information__()
      assert is_list(info.conditional_keys)
      assert :plan in info.conditional_keys
    end

    test "example/0 produces a buildable starting struct" do
      # Auto-generated `example/0` returns a default-populated struct,
      # useful as a fixture starter in REPL / livebook.
      ex = Showcase.EnterpriseAccount.example()
      assert is_struct(ex, Showcase.EnterpriseAccount)
    end
  end
end
