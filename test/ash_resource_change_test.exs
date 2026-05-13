defmodule GuardedStructTest.AshResourceChangeTest do
  use ExUnit.Case, async: false

  # Exercises `GuardedStruct.AshResource.Change` (the bridge module) and
  # `GuardedStruct.Transformers.AutoWireAshChange` (the auto-wire
  # transformer) against REAL Ash resources backed by the ETS data layer.
  # No DB needed; ETS is in-process and ephemeral.

  alias GuardedStructTest.Support.TestDomain

  # ────────────────────────────────────────────────────────────────────
  # Test resources — real Ash, ETS-backed
  # ────────────────────────────────────────────────────────────────────

  defmodule Manual do
    use Ash.Resource,
      domain: TestDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [GuardedStruct.AshResource]

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :email, :string, allow_nil?: false, public?: true
      attribute :nickname, :string, public?: true
    end

    actions do
      defaults [:read, :destroy]
      create :create, accept: [:email, :nickname]
      update :update, accept: [:email, :nickname]
    end

    guardedstruct do
      field :email, :string,
        enforce: true,
        derives: "sanitize(trim, downcase) validate(string, not_empty, email_r)"

      field :nickname, :string,
        derives: "sanitize(trim) validate(string, max_len=20)"
    end

    # Manual wiring — explicit, no auto_wire flag.
    changes do
      change GuardedStruct.AshResource.Change
    end
  end

  defmodule AutoWired do
    use Ash.Resource,
      domain: TestDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [GuardedStruct.AshResource]

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :email, :string, allow_nil?: false, public?: true
    end

    actions do
      defaults [:read, :destroy]
      create :create, accept: [:email]
      update :update, accept: [:email]
    end

    guardedstruct do
      auto_wire true

      field :email, :string,
        enforce: true,
        derives: "sanitize(trim, downcase) validate(string, not_empty, email_r)"
    end
  end

  defmodule AutoWireOff do
    use Ash.Resource,
      domain: TestDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [GuardedStruct.AshResource]

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :email, :string, allow_nil?: false, public?: true
    end

    actions do
      defaults [:read, :destroy]
      create :create, accept: [:email]
    end

    guardedstruct do
      auto_wire false

      field :email, :string, enforce: true, derives: "validate(string)"
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # Change.change/3 — happy path
  # ────────────────────────────────────────────────────────────────────

  describe "Change.change/3 — happy path" do
    test "valid input → changeset.attributes contain sanitized values" do
      changeset =
        Manual
        |> Ash.Changeset.for_create(:create, %{email: "  Alice@X.io  "})

      result = GuardedStruct.AshResource.Change.change(changeset, [], %{})

      # Sanitize ran (trim + downcase). After our Change runs,
      # force_change_attributes wrote the value through to attributes.
      assert result.attributes.email == "alice@x.io"
      assert result.errors == []
      assert result.valid?
    end

    test "preserves changeset identity (still an Ash.Changeset)" do
      changeset =
        Manual
        |> Ash.Changeset.for_create(:create, %{email: "ok@x.com"})

      result = GuardedStruct.AshResource.Change.change(changeset, [], %{})

      assert is_struct(result, Ash.Changeset)
      assert result.resource == Manual
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # Change.change/3 — error paths
  # ────────────────────────────────────────────────────────────────────

  describe "Change.change/3 — error paths" do
    test "missing required guardedstruct field → adds an error" do
      # `:nickname` isn't required by either Ash or guardedstruct, but
      # `:email` is required by both. Skipping :email yields an Ash-level
      # error first (allow_nil?: false). Add a separate field check:
      # provide a value that PASSES Ash's allow_nil but FAILS our derive.
      changeset =
        Manual
        |> Ash.Changeset.for_create(:create, %{email: "ok@x.com", nickname: "way-too-long-nickname-fails-max-len"})

      result = GuardedStruct.AshResource.Change.change(changeset, [], %{})

      refute result.valid?
      assert length(result.errors) >= 1
    end

    test "derive failure with non-string nickname adds an error" do
      # Construct a changeset that bypasses Ash's attribute type check
      # (use change_attribute directly with a value Ash will accept but
      # our derive will reject — e.g., a binary that's too long).
      changeset =
        Manual
        |> Ash.Changeset.for_create(:create, %{
          email: "ok@x.com",
          nickname: String.duplicate("a", 25)
        })

      result = GuardedStruct.AshResource.Change.change(changeset, [], %{})

      refute result.valid?
      assert Enum.any?(result.errors, fn err ->
               # The error structure varies, but the field info is in there.
               inspected = inspect(err)
               String.contains?(inspected, "nickname") or
                 String.contains?(inspected, "max_len")
             end)
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # AutoWireAshChange transformer
  # ────────────────────────────────────────────────────────────────────

  describe "AutoWireAshChange — auto_wire: true" do
    test "Ash.Resource.Info.changes/1 lists our Change module" do
      changes = Ash.Resource.Info.changes(AutoWired)

      assert Enum.any?(changes, fn c ->
               c.change == {GuardedStruct.AshResource.Change, []}
             end),
             "expected GuardedStruct.AshResource.Change in #{inspect(changes)}"
    end

    test "auto-wired resource applies sanitize end-to-end through Ash.create/1" do
      {:ok, user} =
        AutoWired
        |> Ash.Changeset.for_create(:create, %{email: "  Bob@Y.COM  "})
        |> Ash.create()

      # If auto-wire worked, sanitize ran inside Ash's changeset pipeline
      # and the persisted value is the normalized form.
      assert user.email == "bob@y.com"
    end
  end

  describe "AutoWireAshChange — auto_wire: false (default)" do
    test "Manual resource has only the explicitly-added change" do
      changes = Ash.Resource.Info.changes(Manual)

      # Manual added the change explicitly via `changes do change ... end`,
      # so we expect exactly ONE GuardedStruct change — not zero, not two.
      gs_changes =
        Enum.filter(changes, fn c ->
          c.change == {GuardedStruct.AshResource.Change, []}
        end)

      assert length(gs_changes) == 1
    end

    test "AutoWireOff resource has ZERO GuardedStruct changes" do
      changes = Ash.Resource.Info.changes(AutoWireOff)

      refute Enum.any?(changes, fn c ->
               c.change == {GuardedStruct.AshResource.Change, []}
             end)
    end
  end

  describe "AutoWireAshChange — DSL option surface" do
    test "Info.guardedstruct_auto_wire!/1 reflects the option" do
      assert GuardedStruct.AshResource.Info.guardedstruct_auto_wire!(AutoWired) == true
      assert GuardedStruct.AshResource.Info.guardedstruct_auto_wire!(Manual) == false
      assert GuardedStruct.AshResource.Info.guardedstruct_auto_wire!(AutoWireOff) == false
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # Direct __guarded_change__/1 (no changeset)
  # ────────────────────────────────────────────────────────────────────

  describe "direct __guarded_change__/1 API" do
    test "callable outside Ash actions for scripts/tests" do
      assert {:ok, %{email: "alice@x.io"}} =
               AutoWired.__guarded_change__(%{email: "  ALICE@x.io  "})
    end

    test "returns plain map (auto-map cascade) — no struct wrapping" do
      {:ok, result} = Manual.__guarded_change__(%{email: "x@y.com"})
      refute is_struct(result)
    end
  end
end
