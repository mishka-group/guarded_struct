defmodule GuardedStruct.Dsl.ConditionalField do
  @moduledoc false

  defstruct [
    :name,
    :type,
    :enforce,
    :default,
    :derive,
    :validator,
    :auto,
    :from,
    :on,
    :domain,
    :struct,
    :structs,
    :hint,
    :priority,
    fields: [],
    sub_fields: [],
    conditional_fields: [],
    __spark_metadata__: nil
  ]

  @type t :: %__MODULE__{
          name: atom(),
          type: any(),
          enforce: boolean() | nil,
          default: any(),
          derive: any(),
          validator: {module(), atom()} | nil,
          auto: tuple() | nil,
          from: String.t() | nil,
          on: String.t() | nil,
          domain: String.t() | nil,
          struct: module() | nil,
          structs: module() | boolean() | nil,
          hint: String.t() | nil,
          priority: boolean() | nil,
          fields: list(),
          sub_fields: list(),
          conditional_fields: list(),
          __spark_metadata__: any()
        }
end
