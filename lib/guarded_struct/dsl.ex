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

  # `recursive_as: :sub_fields` lets `sub_field` nest inside `sub_field`. We
  # also list the entity in its own `entities[:sub_fields]` slot so the section-
  # macro generator imports `sub_field` inside the body.
  @sub_field_base %Spark.Dsl.Entity{
    name: :sub_field,
    target: GuardedStruct.Dsl.SubField,
    args: [:name, :type],
    schema: [
      name: [type: :atom, required: true],
      type: [type: :quoted, required: true],
      enforce: [type: :boolean],
      default: [type: :quoted],
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

  # `recursive_as: :conditional_fields` lets `conditional_field` nest inside
  # `conditional_field` — this is the headline fix for issues #7/#8/#25.
  @conditional_field_base %Spark.Dsl.Entity{
    name: :conditional_field,
    target: GuardedStruct.Dsl.ConditionalField,
    args: [:name, :type],
    schema: [
      name: [type: :atom, required: true],
      type: [type: :quoted, required: true],
      enforce: [type: :boolean],
      default: [type: :quoted],
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
      sanitize_derive: [type: {:or, [:atom, {:list, :atom}]}]
    ],
    entities: [@field, @sub_field, @conditional_field]
  }

  use Spark.Dsl.Extension,
    sections: [@section],
    transformers: [
      # ParseDerive runs FIRST: validate every `derive: "..."` string at compile
      # time, raising DslError with file:line:column on typos. Closes the
      # headline complaint in REDESIGN.md §10 (legacy silently swallowed bad
      # derives via `rescue _ -> nil`).
      GuardedStruct.Transformers.ParseDerive,
      GuardedStruct.Transformers.GenerateSubFieldModules,
      GuardedStruct.Transformers.GenerateBuilder
    ],
    verifiers: [
      # Verifiers run POST-COMPILE so they can `Code.ensure_loaded?` and
      # `function_exported?` user-supplied modules without forcing them into
      # the compile graph. See REDESIGN.md §G "Verifier vs Transformer".
      GuardedStruct.Verifiers.VerifyValidatorMFA,
      GuardedStruct.Verifiers.VerifyAutoMFA
    ]
end
