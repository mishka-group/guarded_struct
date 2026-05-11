defmodule GuardedStructTest.DeriveExtensionsPerModuleTest do
  @moduledoc """
  Tests the `use GuardedStruct, derive_extensions: [...]` per-module opt
  and the `:config` sentinel that merges the global Application config
  in-position.

  Resolution rules covered:

    * No opt → falls back to global Application config (legacy behavior)
    * `[]`   → opts OUT entirely (no extensions, global ignored)
    * `[A]`  → REPLACE global with [A]
    * `[:config, A]` → global ++ [A] (global wins on :slug-style collisions)
    * `[A, :config]` → [A] ++ global (A wins on collisions)
    * `[A, :config, B]` → [A] ++ global ++ [B] (in-position merge)
    * `[:config, :config]` → ArgumentError at compile time
    * Non-atom entry → ArgumentError at compile time
    * Non-list opt → ArgumentError at compile time
  """

  # async: false — we mutate Application env, which is process-global.
  use ExUnit.Case, async: false

  # Two extension modules with a deliberately overlapping op name `:slug`
  # so we can prove who wins on collisions.

  defmodule GlobalDerives do
    use GuardedStruct.Derive.Extension

    # Accepts only "global:..." prefixed slugs
    validator(:slug, fn input ->
      is_binary(input) and String.starts_with?(input, "global:")
    end)

    # Only here
    validator(:uuid7, fn input -> is_binary(input) end)
  end

  defmodule LocalDerives do
    use GuardedStruct.Derive.Extension

    # Accepts only "local:..." prefixed slugs (collides with GlobalDerives.:slug)
    validator(:slug, fn input ->
      is_binary(input) and String.starts_with?(input, "local:")
    end)

    # Only here
    validator(:ksuid, fn input -> is_binary(input) end)
  end

  defmodule ExtraDerives do
    use GuardedStruct.Derive.Extension

    validator(:phone, fn input -> is_binary(input) end)
  end

  setup do
    # Each test starts with GlobalDerives wired up; we restore afterwards
    # so the suite is hermetic.
    previous = Application.get_env(:guarded_struct, :derive_extensions, [])
    Application.put_env(:guarded_struct, :derive_extensions, [GlobalDerives])
    on_exit(fn -> Application.put_env(:guarded_struct, :derive_extensions, previous) end)
    :ok
  end

  # ---------------- 1. No per-module opt → global is used ----------------

  describe "no derive_extensions: opt → falls back to global config" do
    defmodule NoOpt do
      use GuardedStruct

      guardedstruct do
        field(:slug, String.t(), derives: "validate(slug)")
      end
    end

    test "GlobalDerives.:slug active (only 'global:...' accepted)" do
      assert {:ok, _} = NoOpt.builder(%{slug: "global:hello"})

      assert {:error, errs} = NoOpt.builder(%{slug: "local:hello"})
      assert Enum.any?(errs, &(&1[:field] == :slug and &1[:action] == :slug))
    end

    test "__guarded_derive_extensions_opt__/0 returns nil (no opt set)" do
      assert NoOpt.__guarded_derive_extensions_opt__() == nil
    end
  end

  # ---------------- 2. Empty list → opt-OUT (no extensions at all) ----------------

  describe "derive_extensions: [] → opts out entirely" do
    defmodule EmptyOpt do
      use GuardedStruct, derive_extensions: []

      guardedstruct do
        field(:name, String.t(), derives: "validate(string)")
      end
    end

    test "global is ignored — :slug is no longer known if we tried it" do
      # Use a built-in op so the field still validates; the point is to
      # confirm that the module's extension list resolves to [].
      assert {:ok, _} = EmptyOpt.builder(%{name: "x"})

      assert EmptyOpt.__guarded_derive_extensions_opt__() == []

      resolved =
        GuardedStruct.Derive.Extension.resolve_opt(EmptyOpt.__guarded_derive_extensions_opt__())

      assert resolved == []
    end
  end

  # ---------------- 3. Per-module list (no :config) → REPLACE global ----------------

  describe "derive_extensions: [LocalDerives] → REPLACES global" do
    defmodule ReplaceOpt do
      use GuardedStruct, derive_extensions: [LocalDerives]

      guardedstruct do
        field(:slug, String.t(), derives: "validate(slug)")
      end
    end

    test "LocalDerives.:slug active — only 'local:...' accepted" do
      assert {:ok, _} = ReplaceOpt.builder(%{slug: "local:hello"})

      assert {:error, errs} = ReplaceOpt.builder(%{slug: "global:hello"})
      assert Enum.any?(errs, &(&1[:field] == :slug))
    end

    test "global is COMPLETELY ignored — :uuid7 (only in global) becomes unknown" do
      defmodule ReplaceOptUuid7 do
        use GuardedStruct, derive_extensions: [LocalDerives]

        guardedstruct do
          # :uuid7 exists ONLY in GlobalDerives, which is bypassed entirely
          # since we REPLACE (no :config). The op is unknown to the runtime
          # → fallback_dispatch returns a :type error.
          field(:id, String.t(), derives: "validate(uuid7)")
        end
      end

      assert {:error, errs} = ReplaceOptUuid7.builder(%{id: "anything"})
      assert Enum.any?(errs, &(&1[:field] == :id and &1[:action] == :type))
    end
  end

  # ---------------- 4. [:config, Local] → global ++ [Local], GLOBAL wins ----------------

  describe "derive_extensions: [:config, LocalDerives] → global first" do
    defmodule ConfigFirst do
      use GuardedStruct, derive_extensions: [:config, LocalDerives]

      guardedstruct do
        field(:slug, String.t(), derives: "validate(slug)")
        field(:tag, String.t(), derives: "validate(ksuid)")
      end
    end

    test "GLOBAL :slug wins on collision (first in list)" do
      assert {:ok, _} = ConfigFirst.builder(%{slug: "global:x", tag: "k"})

      # LocalDerives'.slug is shadowed → "local:..." rejected
      assert {:error, errs} = ConfigFirst.builder(%{slug: "local:x", tag: "k"})
      assert Enum.any?(errs, &(&1[:field] == :slug))
    end

    test "non-colliding local op (:ksuid) is still available" do
      assert {:ok, _} = ConfigFirst.builder(%{slug: "global:x", tag: "any-ksuid"})
    end
  end

  # ---------------- 5. [Local, :config] → [Local] ++ global, LOCAL wins ----------------

  describe "derive_extensions: [LocalDerives, :config] → local first" do
    defmodule ConfigLast do
      use GuardedStruct, derive_extensions: [LocalDerives, :config]

      guardedstruct do
        field(:slug, String.t(), derives: "validate(slug)")
        field(:other, String.t(), derives: "validate(uuid7)")
      end
    end

    test "LOCAL :slug wins on collision (first in list)" do
      assert {:ok, _} = ConfigLast.builder(%{slug: "local:x", other: "x"})

      assert {:error, _} = ConfigLast.builder(%{slug: "global:x", other: "x"})
    end

    test "global-only op (:uuid7) still available via fall-through" do
      # uuid7 doesn't exist in LocalDerives — falls through to GlobalDerives
      assert {:ok, _} = ConfigLast.builder(%{slug: "local:x", other: "anything"})
    end
  end

  # ---------------- 6. [A, :config, B] → A ++ global ++ B (in-position) ----------------

  describe "derive_extensions: [LocalDerives, :config, ExtraDerives] → in-position merge" do
    defmodule InPosition do
      use GuardedStruct, derive_extensions: [LocalDerives, :config, ExtraDerives]

      guardedstruct do
        field(:slug, String.t(), derives: "validate(slug)")
        field(:tag, String.t(), derives: "validate(ksuid)")
        field(:tel, String.t(), derives: "validate(phone)")
        field(:id, String.t(), derives: "validate(uuid7)")
      end
    end

    test "LOCAL :slug wins (first in resolved list)" do
      assert {:ok, _} =
               InPosition.builder(%{slug: "local:x", tag: "k", tel: "p", id: "u"})

      assert {:error, _} =
               InPosition.builder(%{slug: "global:x", tag: "k", tel: "p", id: "u"})
    end

    test "ops from all three sources are available" do
      # :ksuid from LocalDerives, :uuid7 from GlobalDerives, :phone from ExtraDerives
      assert {:ok, _} =
               InPosition.builder(%{slug: "local:x", tag: "k", tel: "p", id: "u"})
    end
  end

  # ---------------- 7. Compile-time validation ----------------

  describe "compile-time validation of the opt" do
    test ":config more than once → ArgumentError" do
      msg =
        try do
          Code.eval_string("""
          defmodule DoubleConfig do
            use GuardedStruct, derive_extensions: [:config, :config]
          end
          """)

          :no_raise
        rescue
          e -> Exception.message(e)
        end

      assert is_binary(msg), "expected an ArgumentError, got no raise"
      assert msg =~ ":config more than once"
    end

    test "non-atom entry → ArgumentError" do
      msg =
        try do
          Code.eval_string("""
          defmodule BadEntry do
            use GuardedStruct, derive_extensions: [:config, "not a module"]
          end
          """)

          :no_raise
        rescue
          e -> Exception.message(e)
        end

      assert is_binary(msg)
      assert msg =~ "must be modules or :config"
    end

    test "non-list opt → ArgumentError" do
      msg =
        try do
          Code.eval_string("""
          defmodule NotAList do
            use GuardedStruct, derive_extensions: GlobalDerives
          end
          """)

          :no_raise
        rescue
          e -> Exception.message(e)
        end

      assert is_binary(msg)
      assert msg =~ "expected a list"
    end
  end

  # ---------------- 8. Resolver function — direct unit tests ----------------

  describe "Extension.resolve_opt/1 unit tests" do
    alias GuardedStruct.Derive.Extension

    test "nil → falls back to global" do
      # Global is set to [GlobalDerives] by setup
      assert Extension.resolve_opt(nil) == [GlobalDerives]
    end

    test "empty list → no extensions" do
      assert Extension.resolve_opt([]) == []
    end

    test "[Local] → [Local] (global ignored)" do
      assert Extension.resolve_opt([LocalDerives]) == [LocalDerives]
    end

    test "[:config, Local] → [Global, Local] (in declaration order)" do
      assert Extension.resolve_opt([:config, LocalDerives]) ==
               [GlobalDerives, LocalDerives]
    end

    test "[Local, :config] → [Local, Global]" do
      assert Extension.resolve_opt([LocalDerives, :config]) ==
               [LocalDerives, GlobalDerives]
    end

    test "[A, :config, B] → [A, Global, B]" do
      assert Extension.resolve_opt([LocalDerives, :config, ExtraDerives]) ==
               [LocalDerives, GlobalDerives, ExtraDerives]
    end
  end

  # ---------------- 9. Pdict isolation — nested external-struct builds ----------------

  describe "process dict isolation across nested builders" do
    defmodule UsesLocal do
      use GuardedStruct, derive_extensions: [LocalDerives]

      guardedstruct do
        field(:slug, String.t(), derives: "validate(slug)")
      end
    end

    defmodule UsesGlobal do
      use GuardedStruct

      guardedstruct do
        field(:slug, String.t(), derives: "validate(slug)")
        field(:inner, struct(), struct: UsesLocal)
      end
    end

    test "outer module's extensions don't leak into inner builder" do
      # The outer struct's :slug uses GLOBAL (no opt → global).
      # The inner struct's :slug uses LOCAL (per-module opt).
      # Both must enforce their own rule simultaneously.
      assert {:ok, _} =
               UsesGlobal.builder(%{
                 slug: "global:outer",
                 inner: %{slug: "local:inner"}
               })

      # Outer accepts "global:..." but inner rejects it (it expects "local:...")
      assert {:error, _} =
               UsesGlobal.builder(%{
                 slug: "global:outer",
                 inner: %{slug: "global:outer"}
               })

      # Outer rejects "local:..." while inner accepts it.
      assert {:error, _} =
               UsesGlobal.builder(%{
                 slug: "local:outer",
                 inner: %{slug: "local:inner"}
               })
    end

    test "Process dict is cleaned up after build (no leak between calls)" do
      refute Process.get(:guarded_struct_current_module)
      {:ok, _} = UsesGlobal.builder(%{slug: "global:x", inner: %{slug: "local:y"}})
      refute Process.get(:guarded_struct_current_module)
    end
  end

  # ---------------- 10. Sub_field submodules inherit parent's extensions ----------------

  describe "sub_field submodules use the parent's per-module extensions" do
    defmodule WithSub do
      use GuardedStruct, derive_extensions: [LocalDerives]

      guardedstruct do
        sub_field(:nested, struct()) do
          field(:slug, String.t(), derives: "validate(slug)")
        end
      end
    end

    test "field inside a sub_field uses the parent's :slug extension" do
      # WithSub's parent extension list is [LocalDerives]. The auto-generated
      # WithSub.Nested submodule doesn't have its own use GuardedStruct, so
      # its derive validation should use LocalDerives via the process dict.
      assert {:ok, _} = WithSub.builder(%{nested: %{slug: "local:hello"}})

      assert {:error, _} = WithSub.builder(%{nested: %{slug: "global:hello"}})
    end
  end

  # ---------------- 11. Application.put_env after compile is honoured ----------------

  describe ":config sentinel resolves at lookup time, not compile time" do
    defmodule LazyConfig do
      use GuardedStruct, derive_extensions: [:config, LocalDerives]

      guardedstruct do
        field(:slug, String.t(), derives: "validate(slug)")
      end
    end

    test "swapping the global config affects already-compiled modules" do
      # Setup put [GlobalDerives] globally — LazyConfig accepts "global:..."
      assert {:ok, _} = LazyConfig.builder(%{slug: "global:x"})

      # Now swap the global config to [ExtraDerives] which has no :slug op.
      # LazyConfig should now ONLY have LocalDerives.slug active.
      Application.put_env(:guarded_struct, :derive_extensions, [ExtraDerives])

      try do
        # "global:..." no longer accepted — GlobalDerives is gone
        assert {:error, _} = LazyConfig.builder(%{slug: "global:x"})

        # "local:..." still works — LocalDerives still in the per-module opt
        assert {:ok, _} = LazyConfig.builder(%{slug: "local:x"})
      after
        # The outer setup's on_exit will restore the original; we just
        # restore the test's expected value here so subsequent tests in
        # this describe block aren't affected.
        Application.put_env(:guarded_struct, :derive_extensions, [GlobalDerives])
      end
    end
  end
end
