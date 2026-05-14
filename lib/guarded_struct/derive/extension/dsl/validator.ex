defmodule GuardedStruct.Derive.Extension.Dsl.Validator do
  @moduledoc false

  defstruct [:name, :fun, :__spark_metadata__]

  @type t :: %__MODULE__{
          name: atom(),
          fun: term()
        }
end
