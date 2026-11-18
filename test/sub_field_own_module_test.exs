defmodule GuardedStructTest.SubFieldOwnModuleTest do
  # A sub_field without a do block uses the user's own module of the generated name.
  # async: false — Code.compile_string defines modules globally.
  use ExUnit.Case, async: false

  alias GuardedStructTest.Fixtures.TypedocUses

  defp docs(module) do
    {:docs_v1, _, :elixir, _, moduledoc, _, docs} = Code.fetch_docs(module)
    {_, _, _, typedoc, _} = Enum.find(docs, &match?({{:type, :t, 0}, _, _, _, _}, &1))
    {moduledoc, typedoc}
  end

  describe "an existing module" do
    test "builds the field with the user's module" do
      assert {:ok,
              %TypedocUses{
                address: %TypedocUses.Address{city: "Paris"},
                items: [%TypedocUses.Items{sku: "a"}, %TypedocUses.Items{sku: "b"}]
              }} =
               TypedocUses.builder(%{
                 address: %{city: "Paris"},
                 items: [%{sku: "a"}, %{sku: "b"}]
               })
    end

    test "reports the user's module errors under the field" do
      assert {:error, [%{field: :address, errors: [%{field: :city, action: :required_fields}]}]} =
               TypedocUses.builder(%{address: %{}})

      assert {:error, [%{field: :items, errors: _}]} = TypedocUses.builder(%{items: [%{}]})
    end

    test "is not generated, so its own docs stay as written" do
      assert docs(TypedocUses.Address) |> elem(0) == %{"en" => "The user's own address module."}

      assert docs(TypedocUses.Items) ==
               {%{"en" => "The user's own item module, in another file."},
                %{"en" => "One item, as the user describes it."}}

      # A generated module's info key is the sub_field name; the user's own is :root.
      assert TypedocUses.Address.__information__().key == :root
    end

    test "gives the parent's t() its type and a link to it" do
      {:ok, types} = Code.Typespec.fetch_types(TypedocUses)
      [{:type, spec}] = types
      text = spec |> Code.Typespec.type_to_quoted() |> Macro.to_string()

      assert text =~ "address: GuardedStructTest.Fixtures.TypedocUses.Address.t() | nil"
      assert text =~ "items: [GuardedStructTest.Fixtures.TypedocUses.Items.t()] | nil"

      {_moduledoc, %{"en" => typedoc}} = docs(TypedocUses)

      assert typedoc =~
               "[`GuardedStructTest.Fixtures.TypedocUses.Address.t()`]" <>
                 "(`t:GuardedStructTest.Fixtures.TypedocUses.Address.t/0`)"

      assert typedoc =~ "| Where it is. |"
    end

    test "works for a module defined before the parent in the same file" do
      source = """
      defmodule GuardedStructTest.SubFieldOwnModuleTest.Before.Address do
        use GuardedStruct

        guardedstruct do
          field :city, String.t(), enforce: true
        end
      end

      defmodule GuardedStructTest.SubFieldOwnModuleTest.Before do
        use GuardedStruct

        guardedstruct do
          sub_field :address, struct()
        end
      end
      """

      [_, {parent, _}] = Code.compile_string(source)

      assert {:ok, %{address: %{__struct__: address, city: "Rome"}}} =
               parent.builder(%{address: %{city: "Rome"}})

      assert address == GuardedStructTest.SubFieldOwnModuleTest.Before.Address
    end
  end

  test "a missing module is a compile error" do
    source = """
    defmodule GuardedStructTest.SubFieldOwnModuleTest.Missing do
      use GuardedStruct

      guardedstruct do
        sub_field :address, struct()
      end
    end
    """

    assert_raise Spark.Error.DslError,
                 ~r/sub_field :address has no do block, so it uses the module .*Missing\.Address, but there is no such module with a builder\/1/,
                 fn -> Code.compile_string(source) end
  end

  test "a module without builder/1 is a compile error" do
    source = """
    defmodule GuardedStructTest.SubFieldOwnModuleTest.NoBuilder.Address do
      defstruct [:city]
    end

    defmodule GuardedStructTest.SubFieldOwnModuleTest.NoBuilder do
      use GuardedStruct

      guardedstruct do
        sub_field :address, struct()
      end
    end
    """

    assert_raise Spark.Error.DslError, ~r/no such module with a builder\/1/, fn ->
      Code.compile_string(source)
    end
  end

  test "a do block next to an existing module is still a compile error" do
    source = """
    defmodule GuardedStructTest.SubFieldOwnModuleTest.Block.Address do
      use GuardedStruct

      guardedstruct do
        field :city, String.t()
      end
    end

    defmodule GuardedStructTest.SubFieldOwnModuleTest.Block do
      use GuardedStruct

      guardedstruct do
        sub_field :address, struct() do
          field :street, String.t()
        end
      end
    end
    """

    assert_raise Spark.Error.DslError,
                 ~r/another module with that name is defined.*drop its do block/s,
                 fn -> Code.compile_string(source) end
  end

  test "options that shape a generated module are refused without a do block" do
    source = """
    defmodule GuardedStructTest.SubFieldOwnModuleTest.Shaping.Address do
      use GuardedStruct

      guardedstruct do
        field :city, String.t()
      end
    end

    defmodule GuardedStructTest.SubFieldOwnModuleTest.Shaping do
      use GuardedStruct

      guardedstruct do
        sub_field :address, struct(), authorized_fields: true
      end
    end
    """

    assert_raise Spark.Error.DslError, ~r/:authorized_fields would be ignored/, fn ->
      Code.compile_string(source)
    end
  end
end
