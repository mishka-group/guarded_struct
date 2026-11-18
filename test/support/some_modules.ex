defmodule GuardedStructTest.BasicTypesTest.TestStructNoAlias do
  @moduledoc false
  use GuardedStruct

  guardedstruct do
    field(:test, String.t())
  end
end

defmodule GuardedStructTest.BasicTypesTest.OpaqueTestStruct do
  @moduledoc false
  use GuardedStruct

  guardedstruct opaque: true do
    field(:int, integer())
  end
end

defmodule GuardedStructTest.BasicTypesTest.TestStruct do
  @moduledoc false
  use GuardedStruct

  guardedstruct do
    field(:int, integer())
    field(:string, String.t())
    field(:string_with_default, String.t(), default: "default")
    field(:mandatory_int, integer(), enforce: true)
  end

  def enforce_keys, do: @enforce_keys
end

defmodule GuardedStructTest.BasicTypesTest.TestStruct3 do
  @moduledoc false
  defstruct [:int]

  @opaque t() :: %__MODULE__{int: integer() | nil}
end

defmodule GuardedStructTest.BasicTypesTest.TestStruct2 do
  @moduledoc false
  defstruct [:int, :string, :string_with_default, :mandatory_int]

  @type t() :: %__MODULE__{
          int: integer() | nil,
          string: String.t() | nil,
          string_with_default: String.t(),
          mandatory_int: integer()
        }
end

defmodule TestModule do
  @moduledoc false
  use GuardedStruct

  guardedstruct module: Struct do
    field(:field, term())
  end
end

defmodule TestModule.TestSubModule do
  @moduledoc false
  use GuardedStruct

  guardedstruct do
    field(:field, term())
  end
end

defmodule GuardedStructTest.BasicTypesTest.TestStructWithAlias do
  @moduledoc false
  use GuardedStruct

  guardedstruct do
    alias TestModule.TestSubModule

    field(:test, TestSubModule.t())
  end
end
