defmodule GuardedStructTest.RegistryTest do
  use ExUnit.Case, async: true

  alias GuardedStruct.Derive.Registry

  describe "validate_ops/0 + known_validate?/1" do
    test "includes the core type guards" do
      ops = Registry.validate_ops()

      for name <- [:string, :integer, :atom, :map, :list, :boolean, :float],
          do: assert(MapSet.member?(ops, name), "missing core: #{name}")
    end

    test "includes the named-format validators added on this branch" do
      for name <- [:slug, :hostname, :port_number, :hex_color, :semver] do
        assert Registry.known_validate?(name), "missing format: #{name}"
      end
    end

    test "includes the combinator op atoms (optional + each)" do
      assert Registry.known_validate?(:optional)
      assert Registry.known_validate?(:each)
    end

    test "rejects atoms that are sanitize-only" do
      refute Registry.known_validate?(:trim)
      refute Registry.known_validate?(:downcase)
      refute Registry.known_validate?(:squish)
    end

    test "rejects unknown atoms" do
      refute Registry.known_validate?(:not_a_real_op)
      refute Registry.known_validate?(:strng)
    end
  end

  describe "sanitize_ops/0 + known_sanitize?/1" do
    test "includes the legacy core sanitizers" do
      for name <- [:trim, :upcase, :downcase, :capitalize, :strip_tags] do
        assert Registry.known_sanitize?(name), "missing core sanitizer: #{name}"
      end
    end

    test "includes the list hygiene sanitizers added on this branch" do
      for name <- [:uniq, :compact, :reject_empty, :sort] do
        assert Registry.known_sanitize?(name), "missing list sanitizer: #{name}"
      end
    end

    test "includes the string hygiene sanitizers added on this branch" do
      for name <- [:squish, :no_control, :no_zero_width] do
        assert Registry.known_sanitize?(name), "missing string sanitizer: #{name}"
      end
    end

    test "includes the parameterised sanitizers added on this branch" do
      for name <- [:clamp, :default_when_nil, :default_when_empty, :each] do
        assert Registry.known_sanitize?(name), "missing parameterised sanitizer: #{name}"
      end
    end

    test "rejects atoms that are validate-only" do
      refute Registry.known_sanitize?(:string)
      refute Registry.known_sanitize?(:not_empty)
      refute Registry.known_sanitize?(:slug)
    end
  end

  describe "known_validate?/2 + known_sanitize?/2 — extra ops" do
    test "a built-in op is known whatever the extra ops are" do
      assert Registry.known_validate?(:string, [])
      assert Registry.known_sanitize?(:trim, [])
    end

    test "an op outside the built-in set is known when the extra list holds it" do
      assert Registry.known_validate?(:zz_custom, [:zz_custom])
      assert Registry.known_sanitize?(:zz_shout, [:zz_shout])
    end

    test "an op outside both sets stays unknown" do
      refute Registry.known_validate?(:zz_custom, [])
      refute Registry.known_validate?(:zz_custom, [:other])
      refute Registry.known_sanitize?(:zz_shout, [:other])
    end

    test ":any knows every op" do
      assert Registry.known_validate?(:anything_at_all, :any)
      assert Registry.known_sanitize?(:anything_at_all, :any)
    end

    test "a function returning the extra ops is only called for an op that is not built in" do
      extra = fn ->
        send(self(), :extra_called)
        [:zz_custom]
      end

      assert Registry.known_validate?(:string, extra)
      refute_received :extra_called

      assert Registry.known_validate?(:zz_custom, extra)
      assert_received :extra_called
    end

    test "a function may return :any" do
      assert Registry.known_sanitize?(:whatever, fn -> :any end)
    end
  end
end
