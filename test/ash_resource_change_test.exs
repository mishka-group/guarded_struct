defmodule GuardedStructTest.AshResourceChangeTest do
  use ExUnit.Case, async: false

  # Capture Logger output per-test — Ash's ETS data-layer logs
  # `[debug] Creating ...` during create/update, which we don't want
  # in test output unless a test fails.
  @moduletag capture_log: true

  # Exercises `GuardedStruct.AshResource.Change` (the bridge module) and
  # `GuardedStruct.Transformers.AutoWireAshChange` (the auto-wire
  # transformer) against REAL Ash resources backed by the ETS data layer.
  # No DB needed; ETS is in-process and ephemeral.
  #
  # Test resources live in `test/support/ash_resources.ex` as TOP-LEVEL
  # modules — Spark.Formatter requires top-level resources to apply Ash's
  # paren-removal and section-ordering rules.

  alias GuardedStructTest.AshResources.{Manual, AutoWired, AutoWireOff}

  describe "Change.change/3 — happy path" do
    test "valid input → changeset.attributes contain sanitized values" do
      changeset = Ash.Changeset.for_create(Manual, :create, %{email: "  Alice@X.io  "})

      result = GuardedStruct.AshResource.Change.change(changeset, [], %{})

      assert result.attributes.email == "alice@x.io"
      assert result.errors == []
      assert result.valid?
    end

    test "preserves changeset identity (still an Ash.Changeset)" do
      changeset = Ash.Changeset.for_create(Manual, :create, %{email: "ok@x.com"})

      result = GuardedStruct.AshResource.Change.change(changeset, [], %{})

      assert is_struct(result, Ash.Changeset)
      assert result.resource == Manual
    end
  end

  describe "Change.change/3 — error paths" do
    test "nickname too long → adds an error" do
      changeset =
        Ash.Changeset.for_create(Manual, :create, %{
          email: "ok@x.com",
          nickname: "way-too-long-nickname-fails-max-len"
        })

      result = GuardedStruct.AshResource.Change.change(changeset, [], %{})

      refute result.valid?
      assert length(result.errors) >= 1
    end

    test "derive failure on nickname surfaces an error mentioning the field" do
      changeset =
        Ash.Changeset.for_create(Manual, :create, %{
          email: "ok@x.com",
          nickname: String.duplicate("a", 25)
        })

      result = GuardedStruct.AshResource.Change.change(changeset, [], %{})

      refute result.valid?

      assert Enum.any?(result.errors, fn err ->
               inspected = inspect(err)

               String.contains?(inspected, "nickname") or
                 String.contains?(inspected, "max_len")
             end)
    end
  end

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

      assert user.email == "bob@y.com"
    end
  end

  describe "AutoWireAshChange — auto_wire: false (default)" do
    test "Manual resource has exactly one explicitly-added change" do
      gs_changes =
        Manual
        |> Ash.Resource.Info.changes()
        |> Enum.filter(fn c -> c.change == {GuardedStruct.AshResource.Change, []} end)

      assert length(gs_changes) == 1
    end

    test "AutoWireOff resource has ZERO GuardedStruct changes" do
      refute Enum.any?(Ash.Resource.Info.changes(AutoWireOff), fn c ->
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
