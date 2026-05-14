defmodule GuardedStructFixtures.DynamicFieldFullOptsTest do
  @moduledoc """
  Tests for the 5 newly-added opts on `dynamic_field`: `enforce:`, `auto:`,
  `from:`, `on:`, `domain:`. Previously the schema rejected these — now
  `dynamic_field` has full parity with `field` for cross-field semantics
  (while keeping its free-form-map value shape).
  """

  use ExUnit.Case, async: true

  # ----------------------------------------------------------------
  # enforce: true on a dynamic_field
  # ----------------------------------------------------------------
  describe "enforce: true" do
    defmodule WithEnforce do
      use GuardedStruct

      guardedstruct do
        field(:id, String.t(), enforce: true)
        dynamic_field(:metadata, enforce: true)
      end
    end

    test "rejects build when :metadata is missing" do
      # ERROR REASON: `dynamic_field :metadata, enforce: true` makes
      # :metadata a required key. Input only has :id → :required_fields error.
      assert {:error, _} = WithEnforce.builder(%{id: "x"})
    end

    test "accepts when :metadata is provided" do
      # All enforced keys present; dynamic_field accepts any map value.
      assert {:ok, %{id: "x", metadata: %{a: 1}}} =
               WithEnforce.builder(%{id: "x", metadata: %{a: 1}})
    end
  end

  # ----------------------------------------------------------------
  # auto: — compute the map at build time
  # ----------------------------------------------------------------
  defmodule Computed do
    def default_metadata(_default) do
      %{computed_at: "build_time", source: :auto}
    end
  end

  describe "auto: computed metadata" do
    defmodule WithAuto do
      use GuardedStruct

      guardedstruct do
        field(:id, String.t(), enforce: true)

        dynamic_field(:metadata,
          auto: {Computed, :default_metadata, "unused"}
        )
      end
    end

    test "auto: populates :metadata regardless of user input" do
      # `auto: {Mod, :fn, arg}` calls `Mod.fn(arg)` at build time and uses
      # the return value, IGNORING whatever the user passed. Same semantics
      # as auto: on a regular field.
      assert {:ok, %{metadata: %{computed_at: "build_time", source: :auto}}} =
               WithAuto.builder(%{id: "x"})

      # User-supplied value is silently discarded — auto wins.
      assert {:ok, %{metadata: %{computed_at: "build_time", source: :auto}}} =
               WithAuto.builder(%{id: "x", metadata: %{user: "value"}})
    end
  end

  # ----------------------------------------------------------------
  # from: — pull the value from elsewhere in the input
  # ----------------------------------------------------------------
  describe "from: pulls from another path" do
    defmodule WithFrom do
      use GuardedStruct

      guardedstruct do
        field(:source_data, map(), enforce: true, derives: "validate(map)")

        # Pull metadata from source_data at build time
        dynamic_field(:metadata, from: "root::source_data")
      end
    end

    test "from: copies the value from the named root path" do
      # User only supplied :source_data; `:metadata` is auto-filled from
      # `root::source_data` via from:. Both fields end up with the same map.
      assert {:ok, %{metadata: %{foo: "bar"}, source_data: %{foo: "bar"}}} =
               WithFrom.builder(%{source_data: %{foo: "bar"}})
    end
  end

  # ----------------------------------------------------------------
  # on: — require another field to be present before accepting this one
  # ----------------------------------------------------------------
  describe "on: presence requirement" do
    defmodule WithOn do
      use GuardedStruct

      guardedstruct do
        field(:account_id, String.t())
        dynamic_field(:metadata, on: "root::account_id")
      end
    end

    test "rejects metadata when account_id is missing" do
      # ERROR REASON: `dynamic_field :metadata, on: "root::account_id"`
      # requires `:account_id` to be present in the input before accepting
      # :metadata. Input has :metadata but no :account_id → :dependent_keys.
      assert {:error, _} =
               WithOn.builder(%{metadata: %{any: "value"}})
    end

    test "accepts metadata when account_id is present" do
      # on: dependency satisfied → :metadata accepted.
      assert {:ok, _} =
               WithOn.builder(%{account_id: "acc_x", metadata: %{any: "value"}})
    end
  end

  # ----------------------------------------------------------------
  # domain: — constrain based on a sibling field
  # ----------------------------------------------------------------
  describe "domain: sibling-field constraint" do
    defmodule WithDomain do
      use GuardedStruct

      guardedstruct do
        field(:account_type, String.t(),
          enforce: true,
          derives: "validate(enum=String[free::pro::enterprise])"
        )

        # metadata is only allowed when account_type is in [pro, enterprise]
        dynamic_field(:metadata,
          domain: "!account_type=String[pro, enterprise]"
        )
      end
    end

    test "rejects when account_type doesn't match the domain set" do
      # ERROR REASON: `domain: "!account_type=String[pro, enterprise]"`
      # constrains :metadata's acceptance based on the sibling field. "free"
      # is not in [pro, enterprise] → :domain_parameters error.
      assert {:error, _} =
               WithDomain.builder(%{
                 account_type: "free",
                 metadata: %{a: 1}
               })
    end

    test "accepts when account_type is in the allowed set" do
      # account_type is in the allowed set → domain check passes.
      assert {:ok, _} =
               WithDomain.builder(%{
                 account_type: "pro",
                 metadata: %{a: 1}
               })

      assert {:ok, _} =
               WithDomain.builder(%{
                 account_type: "enterprise",
                 metadata: %{a: 1}
               })
    end
  end

  # ----------------------------------------------------------------
  # ALL 5 in one module
  # ----------------------------------------------------------------
  describe "all five opts together" do
    defmodule AllAtOnce do
      use GuardedStruct

      guardedstruct do
        field(:id, String.t(), enforce: true)

        field(:account_type, String.t(),
          enforce: true,
          derives: "validate(enum=String[free::pro::enterprise])"
        )

        field(:trace_data, map(), derives: "validate(map)")

        dynamic_field(:metadata,
          enforce: true,
          on: "root::id",
          domain: "!account_type=String[pro, enterprise]"
        )

        # Computed/pulled metadata — separate dynamic_fields demonstrating
        # auto: and from: in the same module.
        dynamic_field(:computed_meta, auto: {Computed, :default_metadata, "x"})

        # from: pulls a MAP (dynamic_field requires its value to be a map)
        dynamic_field(:trace_meta, from: "root::trace_data")
      end
    end

    test "all opts apply together — happy path" do
      # enforce, on, and domain checks for :metadata all pass.
      # :computed_meta auto-generated; :trace_meta pulled from :trace_data.
      assert {:ok, built} =
               AllAtOnce.builder(%{
                 id: "x",
                 account_type: "pro",
                 trace_data: %{trace_id: "trace_xyz"},
                 metadata: %{user: "value"}
               })

      assert built.metadata == %{user: "value"}
      assert built.computed_meta == %{computed_at: "build_time", source: :auto}
      assert built.trace_meta == %{trace_id: "trace_xyz"}
    end

    test "enforce: missing :metadata → error" do
      # ERROR REASON: :metadata has `enforce: true` on the dynamic_field.
      # Input lacks it → :required_fields error.
      assert {:error, _} =
               AllAtOnce.builder(%{id: "x", account_type: "pro"})
    end

    test "domain: account_type=free → error" do
      # ERROR REASON: :metadata has `domain:` constraint that requires
      # account_type ∈ [pro, enterprise]. "free" violates → :domain_parameters.
      assert {:error, _} =
               AllAtOnce.builder(%{
                 id: "x",
                 account_type: "free",
                 metadata: %{a: 1}
               })
    end
  end

  # ----------------------------------------------------------------
  # Schema introspection — confirm the new opts appear in __fields__/0
  # (modules defined inside describe blocks live under the test
  # module's namespace, so we use fully-qualified names here)
  # ----------------------------------------------------------------
  alias GuardedStructFixtures.DynamicFieldFullOptsTest, as: T

  describe "__fields__/0 reflects the new opts" do
    test "WithEnforce: :metadata appears in module enforce_keys" do
      # Compile-time check: dynamic_field's enforce: true makes it land in
      # the module's enforce_keys list, same as any other field.
      assert :metadata in T.WithEnforce.enforce_keys()
    end

    test "WithFrom: :metadata's meta carries __from_path__ post-compile" do
      # The from: string gets parsed into a path list by ParseCoreKeys
      # transformer and stored on the field meta for runtime resolution.
      meta = Enum.find(T.WithFrom.__fields__(), &(&1.name == :metadata))
      assert meta.__from_path__ == [:root, :source_data]
    end

    test "WithOn: :metadata's meta carries __on_path__ post-compile" do
      # Same as __from_path__ but for the on: opt.
      meta = Enum.find(T.WithOn.__fields__(), &(&1.name == :metadata))
      assert meta.__on_path__ == [:root, :account_id]
    end

    test "WithDomain: :metadata's meta carries __domain_ops__" do
      # ParseDomain transformer compiles the domain string into an op list.
      meta = Enum.find(T.WithDomain.__fields__(), &(&1.name == :metadata))
      assert is_list(meta.__domain_ops__)
      assert length(meta.__domain_ops__) > 0
    end
  end
end
