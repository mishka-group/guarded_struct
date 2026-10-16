defmodule GuardedStructTest.DeriveSectionOptionsTest do
  @moduledoc """
  The `validate_derive` / `sanitize_derive` section options: the modules that
  serve the ops no built-in clause or derive extension knows. They are tried
  before the application config of the same name, which still serves what they
  leave unhandled.
  """

  # async: false — the application config is process-global.
  use ExUnit.Case, async: false

  alias GuardedStruct.Derive
  alias GuardedStruct.Info
  alias GuardedStruct.Runtime
  alias GuardedStruct.Validate

  defmodule SectionValidate do
    def validate(:section_op, input, _field), do: input <> "|section"
    def validate(:shared_op, input, _field), do: input <> "|section"

    def validate(:section_fails, _input, field),
      do: {:error, field, :section_fails, "section says no"}
  end

  defmodule SecondValidate do
    def validate(:second_op, input, _field), do: input <> "|second"
    def validate(:shared_op, input, _field), do: input <> "|second"
  end

  defmodule AppValidate do
    def validate(:app_op, input, _field), do: input <> "|app"
    def validate(:shared_op, input, _field), do: input <> "|app"
  end

  defmodule SectionSanitize do
    def sanitize(input, :section_op), do: input <> "|section"
    def sanitize(input, :shared_op), do: input <> "|section"
  end

  defmodule SecondSanitize do
    def sanitize(input, :second_op), do: input <> "|second"
  end

  defmodule AppSanitize do
    def sanitize(input, :app_op), do: input <> "|app"
    def sanitize(input, :shared_op), do: input <> "|app"
  end

  defmodule WithSectionOptions do
    use GuardedStruct

    guardedstruct validate_derive: SectionValidate, sanitize_derive: SectionSanitize do
      field(:validated, String.t(), derives: "validate(section_op)")
      field(:sanitized, String.t(), derives: "sanitize(section_op)")
      field(:both, String.t(), derives: "sanitize(section_op) validate(section_op)")
      field(:fails, String.t(), derives: "validate(section_fails)")
      field(:shared, String.t(), derives: "validate(shared_op)")
      field(:shared_sanitized, String.t(), derives: "sanitize(shared_op)")
      field(:app_validated, String.t(), derives: "validate(app_op)")
      field(:app_sanitized, String.t(), derives: "sanitize(app_op)")
      field(:builtin, String.t(), derives: "sanitize(trim, upcase) validate(string)")
    end
  end

  defmodule WithModuleLists do
    use GuardedStruct

    guardedstruct validate_derive: [SectionValidate, SecondValidate],
                  sanitize_derive: [SecondSanitize, SectionSanitize] do
      field(:first, String.t(), derives: "validate(section_op)")
      field(:second, String.t(), derives: "validate(second_op)")
      field(:shared, String.t(), derives: "validate(shared_op)")
      field(:second_sanitized, String.t(), derives: "sanitize(second_op)")
      field(:first_sanitized, String.t(), derives: "sanitize(section_op)")
    end
  end

  defmodule NoSectionOptions do
    use GuardedStruct

    guardedstruct do
      field(:validated, String.t(), derives: "validate(section_op)")
      field(:sanitized, String.t(), derives: "sanitize(section_op)")
      field(:app_validated, String.t(), derives: "validate(app_op)")
      field(:app_sanitized, String.t(), derives: "sanitize(app_op)")
      field(:shared, String.t(), derives: "validate(shared_op)")
    end
  end

  defmodule Inner do
    use GuardedStruct

    guardedstruct do
      field(:value, String.t(), derives: "validate(section_op)")
    end
  end

  defmodule OwnOptions do
    use GuardedStruct

    guardedstruct validate_derive: SecondValidate do
      field(:value, String.t(), derives: "validate(second_op)")
    end
  end

  defmodule WithNested do
    use GuardedStruct

    guardedstruct validate_derive: SectionValidate, sanitize_derive: SectionSanitize do
      field(:top, String.t(), derives: "validate(section_op)")

      field(:external, struct(), struct: Inner)
      field(:own, struct(), struct: OwnOptions)

      sub_field(:profile, struct()) do
        field(:name, String.t(), derives: "sanitize(section_op) validate(section_op)")

        sub_field(:deep, struct()) do
          field(:name, String.t(), derives: "validate(section_op)")
        end
      end

      sub_field(:items, list(struct()), structs: true) do
        field(:name, String.t(), derives: "validate(section_op)")
      end

      conditional_field(:choice, any()) do
        field(:choice, String.t(), derives: "validate(section_op)", hint: "text")

        sub_field(:choice, struct(), hint: "map") do
          field(:name, String.t(), derives: "validate(section_op)")
        end
      end
    end
  end

  setup do
    previous = %{
      validate_derive: Application.get_env(:guarded_struct, :validate_derive),
      sanitize_derive: Application.get_env(:guarded_struct, :sanitize_derive)
    }

    Application.put_env(:guarded_struct, :validate_derive, AppValidate)
    Application.put_env(:guarded_struct, :sanitize_derive, AppSanitize)

    on_exit(fn ->
      for {key, value} <- previous do
        if value,
          do: Application.put_env(:guarded_struct, key, value),
          else: Application.delete_env(:guarded_struct, key)
      end
    end)

    :ok
  end

  describe "validate_derive: section option" do
    test "serves a validate op no built-in clause knows" do
      assert {:ok, %WithSectionOptions{validated: "x|section"}} =
               WithSectionOptions.builder(%{validated: "x"})
    end

    test "its error comes back like any other derive error" do
      assert {:error, errors} = WithSectionOptions.builder(%{fails: "x"})

      assert Enum.any?(
               errors,
               &match?(%{field: :fails, action: :section_fails, message: "section says no"}, &1)
             )
    end

    test "works with no application config at all" do
      Application.delete_env(:guarded_struct, :validate_derive)
      Application.delete_env(:guarded_struct, :sanitize_derive)

      assert {:ok, %WithSectionOptions{validated: "x|section"}} =
               WithSectionOptions.builder(%{validated: "x"})
    end

    test "wins over the application config for an op both serve" do
      assert {:ok, %WithSectionOptions{shared: "x|section"}} =
               WithSectionOptions.builder(%{shared: "x"})
    end

    test "leaves an op it does not handle to the application config" do
      assert {:ok, %WithSectionOptions{app_validated: "x|app"}} =
               WithSectionOptions.builder(%{app_validated: "x"})
    end

    test "a module without the option only has the application config" do
      assert {:error, errors} = NoSectionOptions.builder(%{validated: "x"})
      assert Enum.any?(errors, &match?(%{field: :validated, action: :type}, &1))

      assert {:ok, %NoSectionOptions{app_validated: "x|app", shared: "x|app"}} =
               NoSectionOptions.builder(%{app_validated: "x", shared: "x"})
    end

    test "a list of modules is tried in order" do
      assert {:ok, %WithModuleLists{first: "x|section", second: "x|second", shared: "x|section"}} =
               WithModuleLists.builder(%{first: "x", second: "x", shared: "x"})
    end

    test "an op no module knows is an error, as it is without the option" do
      Application.delete_env(:guarded_struct, :validate_derive)

      assert {:error, errors} = WithSectionOptions.builder(%{app_validated: "x"})
      assert Enum.any?(errors, &match?(%{field: :app_validated, action: :type}, &1))
    end
  end

  describe "sanitize_derive: section option" do
    test "serves a sanitize op no built-in clause knows" do
      assert {:ok, %WithSectionOptions{sanitized: "x|section"}} =
               WithSectionOptions.builder(%{sanitized: "x"})
    end

    test "works with no application config at all" do
      Application.delete_env(:guarded_struct, :sanitize_derive)

      assert {:ok, %WithSectionOptions{sanitized: "x|section"}} =
               WithSectionOptions.builder(%{sanitized: "x"})
    end

    test "wins over the application config for an op both serve" do
      assert {:ok, %WithSectionOptions{shared_sanitized: "x|section"}} =
               WithSectionOptions.builder(%{shared_sanitized: "x"})
    end

    test "leaves an op it does not handle to the application config" do
      assert {:ok, %WithSectionOptions{app_sanitized: "x|app"}} =
               WithSectionOptions.builder(%{app_sanitized: "x"})
    end

    test "sanitize and validate options work in the same group" do
      assert {:ok, %WithSectionOptions{both: "x|section|section"}} =
               WithSectionOptions.builder(%{both: "x"})
    end

    test "built-in ops are not routed through it" do
      assert {:ok, %WithSectionOptions{builtin: "HI"}} =
               WithSectionOptions.builder(%{builtin: "  hi "})
    end

    test "a list of modules is tried in order" do
      assert {:ok, %WithModuleLists{second_sanitized: "x|second", first_sanitized: "x|section"}} =
               WithModuleLists.builder(%{second_sanitized: "x", first_sanitized: "x"})
    end

    test "a module without the option only has the application config" do
      assert {:ok, %NoSectionOptions{sanitized: "x", app_sanitized: "x|app"}} =
               NoSectionOptions.builder(%{sanitized: "x", app_sanitized: "x"})
    end
  end

  describe "nested structs" do
    test "a sub_field of any depth, a list sub_field and a conditional use the root's options" do
      assert {:ok, built} =
               WithNested.builder(%{
                 top: "t",
                 profile: %{name: "n", deep: %{name: "d"}},
                 items: [%{name: "a"}, %{name: "b"}],
                 choice: %{name: "c"}
               })

      assert built.top == "t|section"
      assert built.profile.name == "n|section|section"
      assert built.profile.deep.name == "d|section"
      assert Enum.map(built.items, & &1.name) == ["a|section", "b|section"]
      assert built.choice.name == "c|section"
    end

    test "the conditional's plain child uses them too" do
      assert {:ok, %WithNested{choice: "c|section"}} = WithNested.builder(%{choice: "c"})
    end

    test "a struct: module without options builds under the options of its caller" do
      assert {:ok, %WithNested{external: %Inner{value: "v|section"}}} =
               WithNested.builder(%{external: %{value: "v"}})
    end

    test "a struct: module with options of its own builds under them" do
      assert {:ok, %WithNested{own: %OwnOptions{value: "v|second"}}} =
               WithNested.builder(%{own: %{value: "v"}})
    end

    test "after it, the caller's options apply again" do
      assert {:ok, %WithNested{top: "t|section", own: %OwnOptions{value: "v|second"}}} =
               WithNested.builder(%{top: "t", own: %{value: "v"}})
    end

    test "a sub_field module built on its own keeps the options it inherited" do
      assert {:ok, %WithNested.Profile{name: "n|section|section"}} =
               WithNested.Profile.builder(%{name: "n"})

      assert {:ok, %WithNested.Profile.Deep{name: "d|section"}} =
               WithNested.Profile.Deep.builder(%{name: "d"})
    end

    test "the process is left as it was found" do
      WithNested.builder(%{own: %{value: "v"}})
      assert GuardedStruct.Derive.Extension.current_module() == nil
    end
  end

  describe "Validate.field/4 and Validate.partial/2" do
    test "Validate.field/3 uses the options of the module" do
      assert {:ok, "x|section"} = Validate.field(WithSectionOptions, :validated, "x")
      assert {:ok, "x|section"} = Validate.field(WithSectionOptions, :sanitized, "x")
    end

    test "Validate.partial/2 uses the options of the module" do
      assert {:ok, %{validated: "x|section", sanitized: "y|section"}} =
               Validate.partial(WithSectionOptions, %{validated: "x", sanitized: "y"})
    end

    test "a module without the options keeps the application config only" do
      assert {:error, [%{action: :type}]} = Validate.field(NoSectionOptions, :validated, "x")
    end

    test "the process is left as it was found" do
      Validate.field(WithSectionOptions, :validated, "x")
      Validate.partial(WithSectionOptions, %{validated: "x"})
      assert GuardedStruct.Derive.Extension.current_module() == nil
    end
  end

  describe "Derive.fallback_modules/1" do
    test "is the application config alone when no module is being built" do
      assert Derive.fallback_modules(:validate_derive) == [AppValidate]
      assert Derive.fallback_modules(:sanitize_derive) == [AppSanitize]
    end

    test "puts the options of the module being built first" do
      Runtime.with_current_module(WithModuleLists, fn ->
        assert Derive.fallback_modules(:validate_derive) ==
                 [SectionValidate, SecondValidate, AppValidate]

        assert Derive.fallback_modules(:sanitize_derive) ==
                 [SecondSanitize, SectionSanitize, AppSanitize]
      end)
    end

    test "is empty when nothing is configured" do
      Application.delete_env(:guarded_struct, :validate_derive)

      assert Derive.fallback_modules(:validate_derive) == []

      Runtime.with_current_module(NoSectionOptions, fn ->
        assert Derive.fallback_modules(:validate_derive) == []
      end)
    end

    test "an application config that is a list is kept as it is" do
      Application.put_env(:guarded_struct, :validate_derive, [AppValidate, SecondValidate])

      Runtime.with_current_module(WithSectionOptions, fn ->
        assert Derive.fallback_modules(:validate_derive) ==
                 [SectionValidate, AppValidate, SecondValidate]
      end)
    end
  end

  describe "introspection" do
    test "the options show in the module's information" do
      assert %{validate_derive: SectionValidate, sanitize_derive: SectionSanitize} =
               WithSectionOptions.__information__().options

      assert %{validate_derive: [SectionValidate, SecondValidate]} =
               WithModuleLists.__information__().options
    end

    test "a module that does not set them has no entry for them" do
      refute Map.has_key?(NoSectionOptions.__information__().options, :validate_derive)
      refute Map.has_key?(NoSectionOptions.__information__().options, :sanitize_derive)
    end

    test "Info.describe/1 reports them for the module and for its sub_fields" do
      assert %{validate_derive: SectionValidate, sanitize_derive: SectionSanitize} =
               Info.describe(WithNested).options

      assert %{validate_derive: SectionValidate, sanitize_derive: SectionSanitize} =
               Info.describe(WithNested.Profile).options

      assert %{validate_derive: SectionValidate} = Info.describe(WithNested.Profile.Deep).options
    end

    test "Info.describe/1 reports nil for a module without them" do
      assert %{validate_derive: nil, sanitize_derive: nil} =
               Info.describe(NoSectionOptions).options
    end
  end
end
