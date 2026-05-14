defmodule GuardedStruct.Dsl.Field do
  @moduledoc false

  defstruct [
    :name,
    :type,
    :enforce,
    :default,
    :derive,
    :derives,
    :validator,
    :auto,
    :from,
    :on,
    :domain,
    :struct,
    :structs,
    :hint,
    :priority,
    :__spark_metadata__,
    :__derive_ops__,
    :__from_path__,
    :__on_path__,
    :__domain_ops__,
    # Set to true ONLY for entries from the `dynamic_field` DSL keyword
    # (via Spark `auto_set_fields:`). Used by the runtime to skip
    # recursive atom-conversion of the value — preventing atom-table
    # exhaustion from attacker-controlled keys inside the free-form map.
    __dynamic__: false
  ]

  @type t :: %__MODULE__{
          name: atom(),
          type: any(),
          enforce: boolean() | nil,
          default: any(),
          derive: any(),
          derives: String.t() | nil,
          validator: {module(), atom()} | nil,
          auto: tuple() | nil,
          from: String.t() | nil,
          on: String.t() | nil,
          domain: String.t() | nil,
          struct: module() | nil,
          structs: module() | boolean() | nil,
          hint: String.t() | nil,
          priority: boolean() | nil,
          __spark_metadata__: any(),
          __derive_ops__: map() | nil,
          __from_path__: [atom()] | nil,
          __on_path__: [atom()] | nil,
          __domain_ops__: list() | nil,
          __dynamic__: boolean()
        }
end
