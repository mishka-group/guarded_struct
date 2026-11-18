defmodule GuardedStructTest.EmbeddedFieldShapeTest do
  use ExUnit.Case, async: true

  defmodule Rate do
    use GuardedStruct

    guardedstruct do
      field :name, String.t(), enforce: true, derives: "validate(not_nil_value, string)"
    end
  end

  defmodule Order do
    use GuardedStruct

    guardedstruct do
      field :rates, list(), structs: Rate
      field :rate, struct(), struct: Rate

      sub_field :lines, list(struct()), structs: true do
        field :name, String.t(), enforce: true
      end

      sub_field :address, struct() do
        field :city, String.t(), enforce: true
      end
    end
  end

  describe "a value of the right shape" do
    test "builds every embedded field" do
      assert {:ok,
              %Order{
                rates: [%Rate{name: "fast"}],
                rate: %Rate{name: "slow"},
                lines: [%Order.Lines{name: "one"}],
                address: %Order.Address{city: "Berlin"}
              }} =
               Order.builder(%{
                 rates: [%{name: "fast"}],
                 rate: %{name: "slow"},
                 lines: [%{name: "one"}],
                 address: %{city: "Berlin"}
               })
    end

    test "leaves a missing or nil embedded field nil" do
      assert {:ok, %Order{rates: nil, rate: nil, lines: nil, address: nil}} =
               Order.builder(%{rate: nil})
    end
  end

  describe "a value of the wrong shape" do
    test "a list field given a map or a string is refused, not kept unbuilt" do
      assert {:error, errors} = Order.builder(%{rates: %{name: "x"}, lines: "garbage"})

      assert %{action: :type} = Enum.find(errors, &(&1.field == :rates))
      assert %{action: :type} = Enum.find(errors, &(&1.field == :lines))
    end

    test "a list sub_field given one map is refused instead of building one struct" do
      assert {:error, [%{field: :lines, action: :type}]} =
               Order.builder(%{lines: %{name: "single"}})
    end

    test "a struct field given a list or a scalar is refused" do
      assert {:error, errors} = Order.builder(%{rate: [%{name: "x"}], address: 5})

      assert %{action: :bad_parameters} = Enum.find(errors, &(&1.field == :rate))
      assert %{action: :bad_parameters} = Enum.find(errors, &(&1.field == :address))
    end

    test "the errors become one Splode error per field" do
      {:error, errors} = Order.builder(%{rates: "x", rate: "y"})

      assert %GuardedStruct.Errors.Invalid{errors: validations} =
               GuardedStruct.Errors.from_tuple(errors)

      assert validations |> Enum.map(& &1.field) |> Enum.sort() == [:rate, :rates]
    end
  end
end
