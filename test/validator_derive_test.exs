defmodule GuardedStructTest.ValidatorDeriveTest do
  use ExUnit.Case, async: true

  # TestAuthStruct lives in test/support/ as a shared fixture — used by
  # this file AND test/global_test.exs.
  alias GuardedStructTest.Support.TestAuthStruct

  ############# (▰˘◡˘▰) ValidatorDeriveTest GuardedStructTest Data (▰˘◡˘▰) ##############

  defmodule TestUserAuthStruct do
    use GuardedStruct

    guardedstruct do
      field(:name, String.t(), derives: "validate(not_empty)")
      field(:auth_path, struct(), structs: TestAuthStruct)

      sub_field(:profile, list(struct()), structs: true) do
        field(:github, String.t(), enforce: true, derives: "validate(url)")
        field(:nickname, String.t(), derives: "validate(not_empty)")
      end

      field(:auth_path1, struct(), struct: TestAuthStruct, derives: "validate(map, not_empty)")
      field(:auth_path2, struct(), structs: TestAuthStruct, derives: "validate(list, not_empty)")

      field(:auth_path3, struct(),
        structs: TestAuthStruct,
        derives: "validate(list, not_empty)",
        validator: {__MODULE__, :test_validator}
      )

      sub_field(:profile1, list(struct()), structs: true, derives: "validate(list, not_empty)") do
        field(:github, String.t(), enforce: true, derives: "validate(url)")
        field(:nickname, String.t(), derives: "validate(not_empty)")
      end
    end

    def test_validator(field, value) do
      if is_map(value) and value != %{},
        do: {:ok, field, value},
        else: {:error, field, "No, it is not map"}
    end

    def validator(:name, value) do
      if is_binary(value), do: {:ok, :name, value}, else: {:error, :name, "No, never"}
    end

    # it does not work, because it is sub_field as external module
    def validator(:auth_path2, value) do
      if is_map(value) and value != %{},
        do: {:ok, :auth_path2, value},
        else: {:error, :auth_path2, "No, it is not map"}
    end

    def validator(field, value) do
      {:ok, field, value}
    end
  end

  ############# (▰˘◡˘▰) ValidatorDeriveTest GuardedStructTest Tests (▰˘◡˘▰) ##############
  test "use builder to get validator inside its module" do
    defmodule TestStructInsideValidatorBuilder do
      use GuardedStruct

      guardedstruct do
        field(:name, String.t(), enforce: true)
        field(:title, String.t())
      end

      def validator(:name, value) do
        if is_binary(value), do: {:ok, :name, value}, else: {:error, :name, "No, never"}
      end

      def validator(name, value) do
        {:ok, name, value}
      end
    end

    {:ok, _data} =
      assert TestStructInsideValidatorBuilder.builder(%{name: "shahryar", title: "user"})

    {:error, [%{message: _msg, field: :name}]} =
      assert TestStructInsideValidatorBuilder.builder(%{name: 1, title: "user"})
  end

  test "use builder to get main_validator inside its module" do
    defmodule TestStructInsideMainValidatorBuilder do
      use GuardedStruct

      guardedstruct do
        field(:name, String.t(), enforce: true)
        field(:title, String.t())
      end

      def validator(:name, value) do
        if is_binary(value), do: {:ok, :name, value}, else: {:error, :name, "No, never"}
      end

      def validator(name, value) do
        {:ok, name, value}
      end

      def main_validator(value) do
        {:ok, value}
      end
    end

    {:ok, _data} =
      assert TestStructInsideMainValidatorBuilder.builder(%{name: "mishka", title: "org"})
  end

  test "use builder to get validator inside another module" do
    defmodule GuardedStructTest.AnotherModule do
      def validator(:name, value) do
        if is_binary(value), do: {:ok, :name, value}, else: {:error, :name, "No, never"}
      end
    end

    defmodule TestStructAnotherValidatorBuilder do
      alias GuardedStructTest.AnotherModule
      use GuardedStruct

      guardedstruct do
        field(:name, String.t(), enforce: true, validator: {AnotherModule, :validator})
        field(:title, String.t())
      end

      # You can not use it, but it is mentioned here for test clarity
      def validator(name, value) do
        {:ok, name, value}
      end
    end

    {:ok, _data} =
      assert TestStructAnotherValidatorBuilder.builder(%{name: "mishka", title: "org"})

    {:error, [%{message: _msg, field: :name}]} =
      assert TestStructAnotherValidatorBuilder.builder(%{name: 1, title: "user"})
  end

  test "use builder to get main_validator inside another module" do
    defmodule GuardedStructTest.AnotherMainModule do
      def main_validator(value) do
        {:ok, value}
      end
    end

    defmodule TestStructAnotherMainValidatorBuilder do
      alias GuardedStructTest.AnotherMainModule
      use GuardedStruct

      guardedstruct main_validator: {AnotherMainModule, :main_validator} do
        field(:name, String.t(), enforce: true)
        field(:title, String.t())
      end
    end

    {:ok, _data} =
      assert TestStructAnotherMainValidatorBuilder.builder(%{name: "mishka", title: "org"})
  end

  test "use builder to Sanitize - derive: sanitize(trim, downcase)" do
    defmodule TestStructWithSanitizeDerive do
      use GuardedStruct

      guardedstruct do
        field(:name, String.t(), enforce: true, derives: "sanitize(trim, upcase)")
        field(:title, String.t(), derives: "sanitize(capitalize)")
      end
    end

    {:ok, data} = TestStructWithSanitizeDerive.builder(%{name: " mishka ", title: "org"})
    "MISHKA" = assert data.name
    "Org" = assert data.title
  end

  test "use builder to Validation and Lack of validation" do
    defmodule TestStructWithValidationDerive do
      use GuardedStruct

      guardedstruct do
        field(:name, String.t(), enforce: true, derives: "validate(not_empty)")
        field(:title, String.t(), derives: "validate(not_empty, time)")
      end
    end

    {:error,
     [
       %{message: _msg1, field: :name, action: :not_empty},
       %{message: _msg2, field: :title, action: :type},
       %{message: _msg3, field: :title, action: :not_empty}
     ]} = assert TestStructWithValidationDerive.builder(%{name: "", title: ""})

    defmodule TestStructWithValidationDerive1 do
      use GuardedStruct

      guardedstruct do
        field(:name, String.t(), enforce: true, derives: "validate(not_empty)")
        field(:title, String.t(), derives: "validate(not_empty)")
      end
    end

    {:ok, _data} =
      assert TestStructWithValidationDerive1.builder(%{name: "mishka", title: "group"})
  end

  test "use builder to Sanitize and Validation" do
    defmodule TestStructWithValidationAndValidationDerive do
      use GuardedStruct

      guardedstruct do
        field(:name, String.t(),
          enforce: true,
          derives: "sanitize(trim, upcase) validate(not_empty)"
        )

        field(:title, String.t(), derives: "validate(not_empty)")
      end
    end

    {:ok, data} =
      TestStructWithValidationAndValidationDerive.builder(%{name: " mishka ", title: "org"})

    "MISHKA" = assert data.name

    {:error, [%{message: "The title field must not be empty", field: :title, action: :not_empty}]} =
      assert TestStructWithValidationAndValidationDerive.builder(%{name: " mishka ", title: ""})
  end

  test "use builder to Derive and field validator" do
    defmodule TestStructBuilderWithValidationDeriveAndFieldValidator do
      use GuardedStruct

      guardedstruct do
        field(:name, String.t(),
          enforce: true,
          derives: "sanitize(trim, upcase) validate(not_empty)"
        )

        field(:title, String.t(), derives: "sanitize(trim, capitalize) validate(not_empty)")
      end

      def validator(:name, value) do
        if is_binary(value), do: {:ok, :name, "Mishka   "}, else: {:error, :name, "No, never"}
      end

      def validator(name, value) do
        {:ok, name, value}
      end
    end

    {:ok, data} =
      TestStructBuilderWithValidationDeriveAndFieldValidator.builder(%{
        name: "fake_mishka",
        title: "  org"
      })

    "MISHKA" = assert data.name
    "Org" = assert data.title

    {:error, [%{message: "No, never", field: :name}]} =
      assert TestStructBuilderWithValidationDeriveAndFieldValidator.builder(%{
               name: 1,
               title: "  org"
             })
  end

  test "use builder to Derive and main validator" do
    defmodule TestStructBuilderWithValidationDeriveAndMainValidator do
      use GuardedStruct

      guardedstruct do
        field(:name, String.t(),
          enforce: true,
          derives: "sanitize(trim, upcase) validate(not_empty)"
        )

        field(:title, String.t(), derives: "sanitize(trim, capitalize) validate(not_empty)")
      end

      def main_validator(value) do
        {:ok, Map.merge(value, %{title: "    Group"})}
      end
    end

    {:ok, data} =
      TestStructBuilderWithValidationDeriveAndMainValidator.builder(%{
        name: "mishka",
        title: "  org"
      })

    "MISHKA" = assert data.name
    "Group" = assert data.title
  end

  test "use builder to Derive and both validator and Lack of validation" do
    defmodule TestStructBuilderWithValidationDeriveAndBothValidator do
      use GuardedStruct

      guardedstruct do
        field(:name, String.t(),
          enforce: true,
          derives: "sanitize(trim, upcase) validate(not_empty)"
        )

        field(:title, String.t(), derives: "sanitize(trim, capitalize) validate(not_empty)")
        field(:nickname, String.t(), derives: "validate(not_empty, time)")
      end

      def validator(:name, value) do
        if is_binary(value), do: {:ok, :name, "Mishka   "}, else: {:error, :name, "No, never"}
      end

      def validator(name, value) do
        {:ok, name, value}
      end

      def main_validator(value) do
        {:ok, Map.merge(value, %{title: "    Group"})}
      end
    end

    {:ok, data} =
      TestStructBuilderWithValidationDeriveAndBothValidator.builder(%{
        name: "fake_mishka",
        title: "  org"
      })

    "MISHKA" = assert data.name
    "Group" = assert data.title

    {:error,
     [
       %{message: _msg1, field: :nickname, action: :type},
       %{message: _msg2, field: :nickname, action: :not_empty}
     ]} =
      assert TestStructBuilderWithValidationDeriveAndBothValidator.builder(%{
               name: "fake_mishka",
               nickname: ""
             })
  end

  test "Call struct from another module with validator, derive and main_validator and list attrs" do
    {:ok, _nested_struct} =
      assert TestUserAuthStruct.builder(%{
               name: "mishka",
               auth_path: [
                 %{action: "*:admin", path: %{role: "1"}},
                 %{action: "*:user", path: %{role: "3"}}
               ]
             })

    {:error,
     [
       %{
         field: :auth_path,
         errors: [%{field: :path, errors: [%{message: "No, never", field: :role}]}]
       }
     ]} =
      assert TestUserAuthStruct.builder(%{
               name: "mishka",
               auth_path: [
                 %{action: "*:admin", path: %{role: 1}},
                 %{action: "*:user", path: %{role: "3"}}
               ]
             })

    {:error,
     [
       %{
         field: :auth_path,
         errors: [%{field: :path, errors: [%{message: "No, never", field: :role}]}]
       }
     ]} =
      assert TestUserAuthStruct.builder(%{
               name: "mishka",
               auth_path: [
                 %{action: "*:user", path: %{role: 2, custom_path: "/user"}},
                 %{action: "*:admin", path: %{role: "2"}}
               ]
             })
  end

  test "Call sub_field struct with list attrs and validator, derive and main_validator" do
    {:error, [%{field: :profile, errors: inner_errs}]} =
      assert TestUserAuthStruct.builder(%{
               name: "mishka",
               auth_path: [
                 %{action: "*:admin", path: %{role: "1", rel: %{social: "github"}}},
                 %{action: "*:user", path: %{role: "3", rel: %{social: "github"}}}
               ],
               profile: [%{nickname: "mishka"}, %{nickname: "mishka1"}]
             })

    flat = inner_errs |> List.wrap()
    assert Enum.any?(flat, &match?(%{field: :github, action: :required_fields}, &1))

    {:ok, _nested_struct} =
      assert TestUserAuthStruct.builder(%{
               name: "mishka",
               auth_path: [
                 %{action: "*:admin", path: %{role: "1"}},
                 %{action: "*:user", path: %{role: "3", rel: %{social: "github"}}}
               ],
               profile: [%{github: "https://github.com/mishka-group"}]
             })
  end

  test "custom change data in true state" do
    {:error, [%{message: "No, never", field: :changed, action: :validator}]} =
      TestAuthStruct.builder(%{changed: 1})

    {:ok,
     %GuardedStructTest.Support.TestAuthStruct{
       changed: "https://github.com/mishka-group::Changed",
       path: nil,
       action: nil
     }} =
      TestAuthStruct.builder(%{changed: "https://github.com/mishka-group"})

    {:error,
     [
       %{message: "No, never", field: :changed, action: :validator}
     ]} = assert TestAuthStruct.builder(%{changed: 555_555})

    {:error,
     [
       %{message: "there is an Error", field: :global, action: :main_validator}
     ]} = assert TestAuthStruct.builder(%{changed: "https://github.com/mishka-group", action: 25})
  end

  test "key entries inside derive when derives used" do
    {:error,
     [
       %{
         field: :auth_path1,
         errors: [
           %{
             message: "The auth_path1 field must not be empty",
             field: :auth_path1,
             action: :not_empty
           }
         ]
       },
       %{
         field: :auth_path2,
         errors: [
           %{
             message: "The auth_path2 field must not be empty",
             field: :auth_path2,
             action: :not_empty
           }
         ]
       }
     ]} =
      assert TestUserAuthStruct.builder(%{auth_path1: %{}, auth_path2: []})

    {:error,
     [
       %{
         field: :auth_path3,
         errors: %{
           message: "No, it is not map",
           field: :auth_path3,
           action: :validator
         }
       }
     ]} =
      assert TestUserAuthStruct.builder(%{auth_path3: 1})

    {:ok, _} =
      assert TestUserAuthStruct.builder(%{
               auth_path1: %{action: "admin"},
               auth_path2: [%{action: "admin"}]
             })

    {:error,
     [
       %{
         field: :profile1,
         errors: [
           %{
             message: "The profile1 field must not be empty",
             field: :profile1,
             action: :not_empty
           },
           %{
             message: "The profile1 field must be list",
             field: :profile1,
             action: :list
           }
         ]
       }
     ]} =
      assert TestUserAuthStruct.builder(%{
               profile1: %{}
             })
  end

  ############# (▰˘◡˘▰) main_validator: {Mod, :fun} option (▰˘◡˘▰) ##############

  defmodule MainChecks do
    @moduledoc false

    def reject(attrs) do
      send(self(), {:main_validator_called, :reject, attrs})

      {:error, [%{field: :__root__, action: :main_validator, message: "rejected by MainChecks"}]}
    end

    def reject_one(attrs) do
      send(self(), {:main_validator_called, :reject_one, attrs})
      {:error, %{field: :name, action: :main_validator, message: "one error"}}
    end

    def accept(attrs) do
      send(self(), {:main_validator_called, :accept, attrs})
      {:ok, attrs}
    end

    def stamp(attrs), do: {:ok, Map.put(attrs, :name, "stamped")}

    def ignore(_attrs), do: :anything_else

    def profile_rule(attrs) do
      send(self(), {:profile_rule_called, attrs})

      if Map.get(attrs, :nickname) == "blocked",
        do: {:error, [%{field: :nickname, action: :main_validator, message: "blocked"}]},
        else: {:ok, attrs}
    end
  end

  defmodule MainValidatorSection do
    use GuardedStruct

    guardedstruct main_validator: {MainChecks, :reject} do
      field(:name, String.t())
    end
  end

  defmodule MainValidatorAccepts do
    use GuardedStruct

    guardedstruct main_validator: {MainChecks, :accept} do
      field(:name, String.t())
    end
  end

  defmodule MainValidatorStamps do
    use GuardedStruct

    guardedstruct main_validator: {MainChecks, :stamp} do
      field(:name, String.t())
    end
  end

  defmodule MainValidatorSingleError do
    use GuardedStruct

    guardedstruct main_validator: {MainChecks, :reject_one} do
      field(:name, String.t())
    end
  end

  defmodule MainValidatorIgnored do
    use GuardedStruct

    guardedstruct main_validator: {MainChecks, :ignore} do
      field(:name, String.t())
    end
  end

  defmodule MainValidatorBoth do
    use GuardedStruct

    guardedstruct main_validator: {MainChecks, :accept} do
      field(:name, String.t())
    end

    def main_validator(attrs) do
      send(self(), {:module_main_validator_called, attrs})
      {:error, [%{field: :__root__, action: :main_validator, message: "rejected by module"}]}
    end
  end

  defmodule MainValidatorSelf do
    use GuardedStruct

    guardedstruct main_validator: {__MODULE__, :check} do
      field(:name, String.t())
    end

    def check(attrs) do
      send(self(), {:self_check_called, attrs})
      {:ok, attrs}
    end
  end

  defmodule MainValidatorWithFieldValidator do
    use GuardedStruct

    guardedstruct main_validator: {MainChecks, :accept} do
      field(:name, String.t(), validator: {__MODULE__, :check_name})
      field(:title, String.t())
    end

    def check_name(:name, "ok"), do: {:ok, :name, "ok"}
    def check_name(:name, _value), do: {:error, :name, "bad name"}
  end

  defmodule MainValidatorSubField do
    use GuardedStruct

    guardedstruct do
      field(:top, String.t())

      sub_field(:profile, struct(), main_validator: {MainChecks, :profile_rule}) do
        field(:nickname, String.t())
      end

      sub_field(:accounts, list(struct()),
        structs: true,
        main_validator: {MainChecks, :reject}
      ) do
        field(:id, String.t())
      end
    end

    def main_validator(attrs) do
      send(self(), {:root_main_validator_called, attrs})
      {:ok, attrs}
    end
  end

  describe "main_validator: {Mod, :fun} on the section" do
    test "is called with the validated attrs and its error is returned" do
      assert {:error,
              [%{field: :__root__, action: :main_validator, message: "rejected by MainChecks"}]} =
               MainValidatorSection.builder(%{name: "mishka"})

      assert_received {:main_validator_called, :reject, %{name: "mishka"}}
    end

    test "an {:ok, attrs} builds the struct" do
      assert {:ok, %MainValidatorAccepts{name: "mishka"}} =
               MainValidatorAccepts.builder(%{name: "mishka"})

      assert_received {:main_validator_called, :accept, %{name: "mishka"}}
    end

    test "the attrs it returns are the ones that are built" do
      assert {:ok, %MainValidatorStamps{name: "stamped"}} =
               MainValidatorStamps.builder(%{name: "mishka"})
    end

    test "a single error map comes back inside a list" do
      assert {:error, [%{field: :name, message: "one error"}]} =
               MainValidatorSingleError.builder(%{name: "mishka"})
    end

    test "a return that is neither :ok nor :error leaves the attrs as they were" do
      assert {:ok, %MainValidatorIgnored{name: "mishka"}} =
               MainValidatorIgnored.builder(%{name: "mishka"})
    end

    test "it receives keys that were sent as strings, as atoms" do
      MainValidatorSection.builder(%{"name" => "mishka"})
      assert_received {:main_validator_called, :reject, %{name: "mishka"}}
    end

    test "it wins over a main_validator/1 defined in the module, which is then not called" do
      assert {:ok, %MainValidatorBoth{name: "mishka"}} =
               MainValidatorBoth.builder(%{name: "mishka"})

      assert_received {:main_validator_called, :accept, _attrs}
      refute_received {:module_main_validator_called, _attrs}
    end

    test "it can point at a function of the module that declares it" do
      assert {:ok, %MainValidatorSelf{name: "mishka"}} =
               MainValidatorSelf.builder(%{name: "mishka"})

      assert_received {:self_check_called, %{name: "mishka"}}
    end

    test "a main_validator/1 in the module still runs when the option is not set" do
      assert {:error, [%{action: :main_validator, message: "there is an Error"}]} =
               TestAuthStruct.builder(%{changed: "https://github.com/mishka-group", action: 25})
    end

    test "it gets the attrs of the fields that passed their own validator" do
      assert {:error, [%{field: :name, action: :validator, message: "bad name"}]} =
               MainValidatorWithFieldValidator.builder(%{name: "bad", title: "t"})

      assert_received {:main_validator_called, :accept, attrs}
      assert attrs == %{title: "t"}
    end
  end

  describe "main_validator: {Mod, :fun} on a sub_field" do
    test "is called with the sub_field's attrs and its error is reported on the sub_field" do
      assert {:error, [%{field: :profile, errors: [%{field: :nickname, message: "blocked"}]}]} =
               MainValidatorSubField.builder(%{top: "t", profile: %{nickname: "blocked"}})

      assert_received {:profile_rule_called, %{nickname: "blocked"}}
    end

    test "an {:ok, attrs} lets the sub_field build" do
      assert {:ok,
              %MainValidatorSubField{profile: %MainValidatorSubField.Profile{nickname: "ok"}}} =
               MainValidatorSubField.builder(%{top: "t", profile: %{nickname: "ok"}})
    end

    test "is called for every item of a list sub_field" do
      assert {:error, [%{field: :accounts}]} =
               MainValidatorSubField.builder(%{top: "t", accounts: [%{id: "1"}, %{id: "2"}]})

      assert_received {:main_validator_called, :reject, %{id: "1"}}
    end

    test "the sub_field's module runs it on its own too" do
      assert {:error, [%{field: :nickname, message: "blocked"}]} =
               MainValidatorSubField.Profile.builder(%{nickname: "blocked"})
    end

    test "the main_validator/1 of the parent module does not run for the sub_field" do
      MainValidatorSubField.builder(%{top: "t", profile: %{nickname: "ok"}})

      assert_received {:root_main_validator_called, %{top: "t"}}
      refute_received {:root_main_validator_called, %{nickname: "ok"}}
    end

    test "is kept in the sub_field module's information" do
      assert %{main_validator: {MainChecks, :profile_rule}} =
               MainValidatorSubField.Profile.__information__().options

      assert %{main_validator: {MainChecks, :profile_rule}} =
               GuardedStruct.Info.describe(MainValidatorSubField.Profile).options
    end
  end
end
