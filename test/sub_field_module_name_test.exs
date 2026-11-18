defmodule GuardedStructTest.SubFieldModuleNameTest do
  # async: false — `capture_io(:stderr, ...)` is process-global.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @taken ~r/sub_field :address generates the module .*\.Address, but another module with that name is defined/

  test "a module nested in the parent before guardedstruct is refused" do
    source = """
    defmodule GuardedStructTest.SubFieldModuleNameTest.NestedBefore do
      defmodule Address do
        @moduledoc "Mine."
      end

      use GuardedStruct

      guardedstruct do
        sub_field :address, struct() do
          field :city, String.t()
        end
      end
    end
    """

    assert_raise Spark.Error.DslError, @taken, fn -> Code.compile_string(source) end
  end

  test "a module nested in the parent after guardedstruct is refused" do
    source = """
    defmodule GuardedStructTest.SubFieldModuleNameTest.NestedAfter do
      use GuardedStruct

      guardedstruct do
        sub_field :address, struct() do
          field :city, String.t()
        end
      end

      defmodule Address do
        @moduledoc "Mine."
      end
    end
    """

    assert_raise Spark.Error.DslError, @taken, fn -> Code.compile_string(source) end
  end

  test "a module with the generated name defined before the parent is refused" do
    source = """
    defmodule GuardedStructTest.SubFieldModuleNameTest.Before.Address do
      @moduledoc "Mine."
    end

    defmodule GuardedStructTest.SubFieldModuleNameTest.Before do
      use GuardedStruct

      guardedstruct do
        sub_field :address, struct() do
          field :city, String.t()
        end
      end
    end
    """

    assert_raise Spark.Error.DslError, @taken, fn -> Code.compile_string(source) end
  end

  test "a module that replaces the generated one later is reported" do
    source = """
    defmodule GuardedStructTest.SubFieldModuleNameTest.After do
      use GuardedStruct

      guardedstruct do
        sub_field :address, struct() do
          field :city, String.t()
        end
      end
    end

    defmodule GuardedStructTest.SubFieldModuleNameTest.After.Address do
      @moduledoc "Mine."
    end
    """

    output = capture_io(:stderr, fn -> Code.compile_string(source) end)

    assert output =~ @taken
  end

  test "compiling the same parent again (a recompile) is not refused" do
    source = """
    defmodule GuardedStructTest.SubFieldModuleNameTest.Recompiled do
      use GuardedStruct

      guardedstruct do
        sub_field :address, struct() do
          field :city, String.t()
        end
      end
    end
    """

    output =
      capture_io(:stderr, fn ->
        Code.compile_string(source)
        send(self(), {:compiled, Code.compile_string(source)})
      end)

    refute output =~ "another module with that name"

    assert_received {:compiled, [{module, _beam}]}
    assert {:ok, %{address: %{city: "Berlin"}}} = module.builder(%{address: %{city: "Berlin"}})
  end
end
