defmodule GuardedStructTest.AshResourceTest do
  use ExUnit.Case, async: true

  # We don't depend on :ash for the test suite — instead we define a tiny
  # framework module (`FakeFramework`) that plays the role `Ash.Resource`
  # does for real users. The framework declares which extension kinds it
  # supports, then user modules opt into our extension via
  # `use FakeFramework, extensions: [GuardedStruct.AshResource]`. This is
  # the same wiring Ash uses; we're just replacing the framework.

  defmodule FakeFramework do
    use Spark.Dsl, default_extensions: [extensions: [GuardedStruct.AshResource]]
  end

  defmodule FakeAshResource do
    # Real Ash users do: `use Ash.Resource, extensions: [GuardedStruct.AshResource]`
    # — same wiring as `use FakeFramework, ...` here.
    use FakeFramework

    # Note: Ash users don't get our arity-2 `guardedstruct opts do … end`
    # wrapper (that's auto-imported only by `use GuardedStruct`). Set options
    # via the Spark-generated inline setters at the top of the block — this
    # is idiomatic Spark.
    guardedstruct do
      field(:email, :string,
        enforce: true,
        derives: "sanitize(trim, downcase) validate(string, not_empty, email_r)"
      )

      field(:nickname, :string,
        derives: "sanitize(strip_tags, trim) validate(string, max_len=20)"
      )

      sub_field(:preferences, :map) do
        field(:theme, :string, derives: "validate(enum=String[light::dark])")
      end
    end
  end

  describe "Ash extension generates introspection functions" do
    test "__guarded_information__/0 returns the metadata map" do
      info = FakeAshResource.__guarded_information__()
      assert info.module == FakeAshResource
      assert :email in info.keys
      assert :nickname in info.keys
      assert :preferences in info.keys
    end

    test "__guarded_fields__/0 returns runtime field metadata" do
      meta = FakeAshResource.__guarded_fields__()
      assert is_list(meta)
      assert Enum.any?(meta, &(&1.name == :email))
    end

    test "does NOT generate __struct__/builder/2 (Ash owns those)" do
      refute function_exported?(FakeAshResource, :builder, 1)
      refute function_exported?(FakeAshResource, :builder, 2)
      refute function_exported?(FakeAshResource, :__struct__, 0)
    end
  end

  describe "__guarded_change__/1" do
    test "valid input → {:ok, sanitized_attrs}" do
      assert {:ok, attrs} =
               FakeAshResource.__guarded_change__(%{email: "  Foo@Bar.COM  "})

      # Sanitize ran (trim + downcase).
      assert attrs.email == "foo@bar.com"
    end

    test "missing required field → {:error, required_fields}" do
      assert {:error, %{action: :required_fields, fields: [:email]}} =
               FakeAshResource.__guarded_change__(%{})
    end

    test "derive failure → {:error, list of errors}" do
      assert {:error, errs} =
               FakeAshResource.__guarded_change__(%{
                 email: "valid@example.com",
                 nickname: 123
               })

      assert Enum.any?(errs, fn e -> e.field == :nickname end)
    end

    test "sub_field validation works through the Ash variant too" do
      # `theme` has an enum derive — wrong value should fail.
      assert {:error, errors} =
               FakeAshResource.__guarded_change__(%{
                 email: "valid@example.com",
                 preferences: %{theme: "blue"}
               })

      # Should mention the preferences sub-tree.
      assert Enum.any?(errors, fn e -> Map.get(e, :field) == :preferences end)

      # And valid sub_field input passes through.
      assert {:ok, attrs} =
               FakeAshResource.__guarded_change__(%{
                 email: "valid@example.com",
                 preferences: %{theme: "dark"}
               })

      assert attrs.preferences.theme == "dark"
    end
  end

  describe "GuardedStruct.AshResource.Info" do
    test "fields/1 returns declared field names" do
      assert GuardedStruct.AshResource.Info.fields(FakeAshResource) ==
               [:email, :nickname, :preferences]
    end

    test "field/2 returns metadata for a name" do
      assert %{kind: :field, name: :email} =
               GuardedStruct.AshResource.Info.field(FakeAshResource, :email)
    end

    test "field?/2 boolean membership" do
      assert GuardedStruct.AshResource.Info.field?(FakeAshResource, :email)
      refute GuardedStruct.AshResource.Info.field?(FakeAshResource, :no_such)
    end

    test "validate/2 delegates to __guarded_change__/1" do
      assert {:ok, _} =
               GuardedStruct.AshResource.Info.validate(FakeAshResource, %{
                 email: "ok@x.com"
               })
    end

    test "Spark-generated guardedstruct_enforce!/1 reads the section option" do
      # No block-level enforce was set, so this is the default (false).
      assert GuardedStruct.AshResource.Info.guardedstruct_enforce!(FakeAshResource) ==
               false
    end
  end
end
