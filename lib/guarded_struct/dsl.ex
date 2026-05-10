defmodule GuardedStruct.Dsl do
  @moduledoc false

  @field %Spark.Dsl.Entity{
    name: :field,
    target: GuardedStruct.Dsl.Field,
    args: [:name, :type],
    schema: [
      name: [type: :any, required: true],
      type: [type: :quoted, required: true],
      enforce: [type: :boolean],
      default: [type: :quoted],
      derives: [type: :string],
      derive: [type: :string],
      validator: [type: {:tuple, [:atom, :atom]}],
      auto: [
        type:
          {:or,
           [
             {:tuple, [:atom, :atom]},
             {:tuple, [:atom, :atom, :any]}
           ]}
      ],
      from: [type: :string],
      on: [type: :string],
      domain: [type: :string],
      struct: [type: :atom],
      structs: [type: {:or, [:atom, :boolean]}],
      hint: [type: :string],
      priority: [type: :boolean]
    ]
  }

  @virtual_field %Spark.Dsl.Entity{
    name: :virtual_field,
    target: GuardedStruct.Dsl.VirtualField,
    args: [:name, :type],
    schema: [
      name: [type: :any, required: true],
      type: [type: :quoted, required: true],
      enforce: [type: :boolean],
      default: [type: :quoted],
      derives: [type: :string],
      derive: [type: :string],
      validator: [type: {:tuple, [:atom, :atom]}],
      auto: [
        type:
          {:or,
           [
             {:tuple, [:atom, :atom]},
             {:tuple, [:atom, :atom, :any]}
           ]}
      ],
      from: [type: :string],
      on: [type: :string],
      domain: [type: :string],
      hint: [type: :string]
    ]
  }

  @dynamic_field %Spark.Dsl.Entity{
    name: :dynamic_field,
    target: GuardedStruct.Dsl.Field,
    args: [:name],
    schema: [
      name: [type: :any, required: true],
      type: [type: :quoted, default: quote(do: map())],
      default: [type: :quoted, default: Macro.escape(%{})],
      derives: [type: :string, default: "validate(map)"],
      derive: [type: :string],
      validator: [type: {:tuple, [:atom, :atom]}],
      hint: [type: :string]
    ]
  }

  @sub_field_base %Spark.Dsl.Entity{
    name: :sub_field,
    target: GuardedStruct.Dsl.SubField,
    args: [:name, :type],
    schema: [
      name: [type: :atom, required: true],
      type: [type: :quoted, required: true],
      enforce: [type: :boolean],
      default: [type: :quoted],
      derives: [type: :string],
      derive: [type: :string],
      validator: [type: {:tuple, [:atom, :atom]}],
      auto: [
        type:
          {:or,
           [
             {:tuple, [:atom, :atom]},
             {:tuple, [:atom, :atom, :any]}
           ]}
      ],
      from: [type: :string],
      on: [type: :string],
      domain: [type: :string],
      struct: [type: :atom],
      structs: [type: {:or, [:atom, :boolean]}],
      hint: [type: :string],
      priority: [type: :boolean],
      error: [type: :boolean],
      authorized_fields: [type: :boolean],
      main_validator: [type: {:tuple, [:atom, :atom]}]
    ],
    recursive_as: :sub_fields,
    entities: [
      fields: [@field],
      sub_fields: [],
      conditional_fields: []
    ]
  }

  @conditional_field_base %Spark.Dsl.Entity{
    name: :conditional_field,
    target: GuardedStruct.Dsl.ConditionalField,
    args: [:name, :type],
    schema: [
      name: [type: :atom, required: true],
      type: [type: :quoted, required: true],
      enforce: [type: :boolean],
      default: [type: :quoted],
      derives: [type: :string],
      derive: [type: :string],
      validator: [type: {:tuple, [:atom, :atom]}],
      auto: [
        type:
          {:or,
           [
             {:tuple, [:atom, :atom]},
             {:tuple, [:atom, :atom, :any]}
           ]}
      ],
      from: [type: :string],
      on: [type: :string],
      domain: [type: :string],
      struct: [type: :atom],
      structs: [type: {:or, [:atom, :boolean]}],
      hint: [type: :string],
      priority: [type: :boolean]
    ],
    recursive_as: :conditional_fields,
    entities: [
      fields: [@field],
      sub_fields: [@sub_field_base],
      conditional_fields: []
    ]
  }

  @sub_field %{
    @sub_field_base
    | entities:
        @sub_field_base.entities
        |> Keyword.put(:sub_fields, [@sub_field_base])
        |> Keyword.put(:conditional_fields, [@conditional_field_base])
  }

  @conditional_field %{
    @conditional_field_base
    | entities:
        @conditional_field_base.entities
        |> Keyword.put(:conditional_fields, [@conditional_field_base])
        |> Keyword.put(:sub_fields, [@sub_field])
  }

  @section %Spark.Dsl.Section{
    name: :guardedstruct,
    schema: [
      enforce: [type: :boolean, default: false],
      opaque: [type: :boolean, default: false],
      module: [type: :quoted],
      error: [type: :boolean, default: false],
      authorized_fields: [type: :boolean, default: false],
      main_validator: [type: {:tuple, [:atom, :atom]}],
      validate_derive: [type: {:or, [:atom, {:list, :atom}]}],
      sanitize_derive: [type: {:or, [:atom, {:list, :atom}]}],
      jason: [type: :boolean, default: false]
    ],
    entities: [@field, @virtual_field, @dynamic_field, @sub_field, @conditional_field]
  }

  use Spark.Dsl.Extension,
    sections: [@section],
    transformers: [
      GuardedStruct.Transformers.ParseDerive,
      GuardedStruct.Transformers.VerifyDeriveOps,
      GuardedStruct.Transformers.ParseCoreKeys,
      GuardedStruct.Transformers.VerifyCoreKeyPaths,
      GuardedStruct.Transformers.ParseDomain,
      GuardedStruct.Transformers.GenerateSubFieldModules,
      GuardedStruct.Transformers.GenerateBuilder
    ],
    verifiers: [
      GuardedStruct.Verifiers.VerifyValidatorMFA,
      GuardedStruct.Verifiers.VerifyAutoMFA,
      GuardedStruct.Verifiers.VerifyNoStructCycles
    ]
end
