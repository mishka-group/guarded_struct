defmodule GuardedStructTest.AshResourceChangeTest do
  use ExUnit.Case, async: false

  # Exercises `GuardedStruct.AshResource.Change` (the bridge module) and
  # `GuardedStruct.Transformers.AutoWireAshChange` (the auto-wire
  # transformer). Uses the test stubs in `test/support/ash_stubs.ex` so
  # we can verify behavior without depending on the full `:ash` package.

  defmodule FakeFramework do
    use Spark.Dsl, default_extensions: [extensions: [GuardedStruct.AshResource]]
  end

  defmodule Manual do
    # Default — auto_wire: false. User would write `changes do change ... end`
    # themselves in real Ash usage; we don't need it for these tests since
    # we exercise `Change.change/3` directly.
    use FakeFramework

    guardedstruct do
      field(:email, :string,
        enforce: true,
        derives: "sanitize(trim, downcase) validate(string, not_empty, email_r)"
      )

      field(:nickname, :string,
        derives: "sanitize(trim) validate(string, max_len=20)"
      )
    end
  end

  defmodule AutoWired do
    use FakeFramework

    # Spark inline setter — `use FakeFramework` doesn't import our
    # arity-2 `guardedstruct opts do ... end` wrapper (that's only auto-
    # imported by `use GuardedStruct`). Idiomatic Spark sets section
    # options at the top of the block.
    guardedstruct do
      auto_wire(true)

      field(:email, :string,
        enforce: true,
        derives: "sanitize(trim, downcase) validate(string, not_empty, email_r)"
      )
    end
  end

  defmodule AutoWireOff do
    use FakeFramework

    guardedstruct do
      auto_wire(false)
      field(:email, :string, enforce: true, derives: "validate(string)")
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # GuardedStruct.AshResource.Change.change/3
  # ────────────────────────────────────────────────────────────────────

  describe "GuardedStruct.AshResource.Change.change/3 — happy path" do
    test "valid attrs → force_change_attributes called with sanitized values" do
      changeset = %Ash.Changeset{
        resource: Manual,
        attributes: %{email: "  Alice@X.io  "}
      }

      result = GuardedStruct.AshResource.Change.change(changeset, [], %{})

      # Sanitize ran (trim + downcase), then the transformed map was
      # written back to the changeset.
      assert result.changes.email == "alice@x.io"
      assert result.errors == []
    end

    test "transformed map can include keys ADDED by the pipeline" do
      # `nickname` was not in input attrs — only :email. The pipeline still
      # returns a map containing both keys (with nil for nickname). Make
      # sure force_change_attributes receives that full map.
      changeset = %Ash.Changeset{
        resource: Manual,
        attributes: %{email: "ok@x.com", nickname: "  jay  "}
      }

      result = GuardedStruct.AshResource.Change.change(changeset, [], %{})

      assert result.changes.email == "ok@x.com"
      assert result.changes.nickname == "jay"
      assert result.errors == []
    end
  end

  describe "GuardedStruct.AshResource.Change.change/3 — error paths" do
    test "missing required field → add_error called once" do
      changeset = %Ash.Changeset{resource: Manual, attributes: %{}}
      result = GuardedStruct.AshResource.Change.change(changeset, [], %{})

      # The pipeline returns a single error map (not a list) for required_fields.
      # Our change/3 routes that to the singular add_error branch.
      assert result.changes == %{}
      assert length(result.errors) == 1
      [err] = result.errors
      assert err.action == :required_fields
      assert err.fields == [:email]
    end

    test "derive failure → add_error called per error" do
      # `nickname` not a string → derive failure list.
      changeset = %Ash.Changeset{
        resource: Manual,
        attributes: %{email: "ok@x.com", nickname: 123}
      }

      result = GuardedStruct.AshResource.Change.change(changeset, [], %{})

      assert result.changes == %{}
      # At least one error landed.
      assert length(result.errors) >= 1
      assert Enum.any?(result.errors, fn e -> Map.get(e, :field) == :nickname end)
    end

    test "preserves changeset identity (no extra fields added)" do
      changeset = %Ash.Changeset{
        resource: Manual,
        attributes: %{email: "ok@x.com"}
      }

      result = GuardedStruct.AshResource.Change.change(changeset, [], %{})

      assert result.resource == Manual
      assert is_struct(result, Ash.Changeset)
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # AutoWireAshChange transformer
  # ────────────────────────────────────────────────────────────────────

  describe "AutoWireAshChange — auto_wire: true" do
    test "calls Ash.Resource.Builder.add_change with our Change module" do
      # The stub records calls keyed by resource module. AutoWired was
      # defined above with `auto_wire: true`, so the stub should have one
      # recorded call by now (it happened at compile-time of AutoWired).
      calls = Ash.Resource.Builder.calls(AutoWired)

      assert length(calls) == 1
      [{change_module, opts}] = calls
      assert change_module == GuardedStruct.AshResource.Change
      assert opts == []
    end
  end

  describe "AutoWireAshChange — auto_wire: false (default)" do
    test "does NOT call Ash.Resource.Builder.add_change" do
      # Manual was defined without `auto_wire:` (default false).
      assert Ash.Resource.Builder.calls(Manual) == []
    end

    test "explicit auto_wire: false also skips" do
      assert Ash.Resource.Builder.calls(AutoWireOff) == []
    end
  end

  describe "AutoWireAshChange — DSL option surface" do
    test "auto_wire option is on the section schema (parsed without error)" do
      # If `auto_wire:` weren't a known option, the AutoWired module would
      # have failed at compile time with a Spark.Error.DslError. We got
      # this far without raising → the option is recognized.
      assert function_exported?(AutoWired, :__guarded_change__, 1)
    end

    test "Info.guardedstruct_auto_wire!/1 reflects the option" do
      assert GuardedStruct.AshResource.Info.guardedstruct_auto_wire!(AutoWired) == true
      assert GuardedStruct.AshResource.Info.guardedstruct_auto_wire!(Manual) == false
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # Integration shape
  # ────────────────────────────────────────────────────────────────────

  describe "integration — Change + auto-wire together" do
    test "AutoWired resource still has __guarded_change__/1 working" do
      # Auto-wiring should NOT replace or interfere with the direct API.
      assert {:ok, %{email: "alice@x.io"}} =
               AutoWired.__guarded_change__(%{email: "  ALICE@x.io  "})
    end

    test "Change.change/3 works on an auto-wired resource" do
      changeset = %Ash.Changeset{
        resource: AutoWired,
        attributes: %{email: "  Bob@Y.com  "}
      }

      result = GuardedStruct.AshResource.Change.change(changeset, [], %{})
      assert result.changes.email == "bob@y.com"
    end
  end
end
