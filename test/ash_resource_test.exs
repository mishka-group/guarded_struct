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

  defmodule FakeChecks do
    def verify(attrs) do
      if Map.get(attrs, :name) == "blocked",
        do: {:error, [%{field: :name, action: :main_validator, message: "name is blocked"}]},
        else: {:ok, attrs}
    end

    def validate(:fake_op, input, _field), do: input
    def sanitize(input, :fake_op), do: input <> "!"
  end

  defmodule FakeAshWithDomain do
    use FakeFramework

    guardedstruct do
      field(:status, :string, domain: "!auth_type=Atom[admin, moderator]")
      field(:note, :string, domain: "?auth_type=Atom[admin]")
      field(:auth_type, :atom)
      field(:src, :string)
      field(:copy, :string, from: "root::src")
      field(:gate, :string, on: "root::src")

      sub_field(:settings, :map) do
        field(:mode, :string, domain: "!auth_type=Atom[admin]")
      end
    end
  end

  defmodule FakeAshWithOptions do
    use FakeFramework

    guardedstruct do
      main_validator({FakeChecks, :verify})
      validate_derive(FakeChecks)
      sanitize_derive(FakeChecks)

      field(:name, :string, derives: "sanitize(fake_op) validate(fake_op)")
      field(:score, :integer, derives: "sanitize(default_when_nil=0, clamp=[0, 100])")
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

    test "missing required field → {:error, [required_fields]}" do
      assert {:error, [%{field: :email, action: :required_fields}]} =
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

  describe "domain: rules (same transformer as the standalone DSL)" do
    test "a value inside the domain passes" do
      for auth_type <- [:admin, :moderator] do
        assert {:ok, %{status: "x"}} =
                 FakeAshWithDomain.__guarded_change__(%{status: "x", auth_type: auth_type})
      end
    end

    test "a value outside the domain is refused with :domain_parameters" do
      assert {:error, errors} =
               FakeAshWithDomain.__guarded_change__(%{status: "x", auth_type: :guest})

      assert Enum.any?(errors, &match?(%{field: :status, action: :domain_parameters}, &1))
    end

    test "a ! rule refuses a missing domain field" do
      assert {:error, errors} = FakeAshWithDomain.__guarded_change__(%{status: "x"})
      assert Enum.any?(errors, &match?(%{field: :status, action: :domain_parameters}, &1))
    end

    test "a ? rule lets a missing domain field through, and still checks one that is there" do
      assert {:ok, _} = FakeAshWithDomain.__guarded_change__(%{note: "n"})

      assert {:error, errors} =
               FakeAshWithDomain.__guarded_change__(%{note: "n", auth_type: :guest})

      assert Enum.any?(errors, &match?(%{field: :note, action: :domain_parameters}, &1))
    end

    test "a field with no value is not checked" do
      assert {:ok, _} = FakeAshWithDomain.__guarded_change__(%{})
    end

    test "a rule on a sub_field's field uses the root's value" do
      assert {:ok, _} =
               FakeAshWithDomain.__guarded_change__(%{auth_type: :admin, settings: %{mode: "m"}})

      assert {:error, [%{field: :settings, errors: errors}]} =
               FakeAshWithDomain.__guarded_change__(%{auth_type: :guest, settings: %{mode: "m"}})

      assert Enum.any?(errors, &match?(%{field: :mode, action: :domain_parameters}, &1))
    end

    test "the parsed rules are baked into the field metadata" do
      assert [%{required?: true, field_path: "auth_type"}] =
               FakeAshWithDomain.__guarded_field_meta__(:status).__domain_ops__

      assert [%{required?: false, field_path: "auth_type"}] =
               FakeAshWithDomain.__guarded_field_meta__(:note).__domain_ops__

      assert FakeAshWithDomain.__guarded_field_meta__(:auth_type).__domain_ops__ == nil
    end

    test "the from: and on: paths are baked too" do
      assert FakeAshWithDomain.__guarded_field_meta__(:copy).__from_path__ == [:root, :src]
      assert FakeAshWithDomain.__guarded_field_meta__(:gate).__on_path__ == [:root, :src]
    end

    test "from: and on: still work" do
      assert {:ok, %{copy: "x"}} = FakeAshWithDomain.__guarded_change__(%{src: "x"})
      assert {:error, errors} = FakeAshWithDomain.__guarded_change__(%{gate: "g"})
      assert Enum.any?(errors, &match?(%{field: :gate, action: :dependent_keys}, &1))
    end
  end

  describe "section options" do
    test "main_validator {Mod, :fun} is called" do
      assert {:error, [%{field: :name, action: :main_validator, message: "name is blocked"}]} =
               FakeAshWithOptions.__guarded_change__(%{name: "blocked"})

      assert {:ok, _} = FakeAshWithOptions.__guarded_change__(%{name: "fine"})
    end

    test "validate_derive and sanitize_derive serve their ops" do
      assert {:ok, %{name: "fine!"}} = FakeAshWithOptions.__guarded_change__(%{name: "fine"})
    end

    test "default_when_nil fills a nil or missing field" do
      assert {:ok, %{score: 0}} = FakeAshWithOptions.__guarded_change__(%{name: "fine"})

      assert {:ok, %{score: 0}} =
               FakeAshWithOptions.__guarded_change__(%{name: "fine", score: nil})

      assert {:ok, %{score: 100}} =
               FakeAshWithOptions.__guarded_change__(%{name: "fine", score: 900})
    end

    test "they show in __guarded_information__/0" do
      assert %{
               main_validator: {FakeChecks, :verify},
               validate_derive: FakeChecks,
               sanitize_derive: FakeChecks
             } = FakeAshWithOptions.__guarded_information__().options
    end

    test "a resource that sets none has none in its options" do
      options = FakeAshResource.__guarded_information__().options
      refute Map.has_key?(options, :main_validator)
      refute Map.has_key?(options, :validate_derive)
    end

    test "the process is left as it was found" do
      FakeAshWithOptions.__guarded_change__(%{name: "fine"})
      assert GuardedStruct.Derive.Extension.current_module() == nil
    end
  end
end
