defmodule GuardedStructTest.Fixtures.NestedConditionalField.Actor do
  use GuardedStruct
  @types ["Application", "Group", "Organization", "Person", "Service"]

  guardedstruct do
    field :id, String.t(), derives: "sanitize(tag=strip_tags) validate(url)"

    field :type, String.t(),
      derives: "sanitize(tag=strip_tags) validate(enum=String[#{Enum.join(@types, "::")}])",
      default: "Person"

    field :summary, String.t(),
      enforce: true,
      derives: "sanitize(tag=strip_tags) validate(not_empty_string, max_len=364, min_len=3)"
  end
end

defmodule GuardedStructTest.Fixtures.NestedConditionalField.Conditional do
  use GuardedStruct
  alias ConditionalFieldValidatorTestValidators, as: VAL
  alias GuardedStructTest.Fixtures.NestedConditionalField.Actor

  guardedstruct do
    conditional_field :actor, any() do
      field :actor, struct(), struct: Actor, validator: {VAL, :is_map_data}

      conditional_field :actor, any(), structs: true, validator: {VAL, :is_list_data} do
        field :actor, struct(), struct: Actor, validator: {VAL, :is_map_data}

        field :actor, String.t(),
          validator: {VAL, :is_string_data},
          derives: "sanitize(tag=strip_tags) validate(url, max_len=160)"
      end

      field :actor, String.t(),
        validator: {VAL, :is_string_data},
        derives: "sanitize(tag=strip_tags) validate(url, max_len=160)"
    end
  end
end

defmodule GuardedStructTest.Fixtures.NestedConditionalField.TripleNest do
  use GuardedStruct
  alias ConditionalFieldValidatorTestValidators, as: VAL

  guardedstruct do
    conditional_field :choice, any() do
      field :choice, String.t(), validator: {VAL, :is_string_data}, hint: "level1_string"

      conditional_field :choice, any(), validator: {VAL, :is_map_data} do
        field :choice, String.t(), validator: {VAL, :is_string_data}, hint: "level2_string"

        conditional_field :choice, any(), validator: {VAL, :is_map_data} do
          field :choice, String.t(),
            validator: {VAL, :is_string_data},
            hint: "level3_string"

          field :choice, :integer, validator: {VAL, :is_int_data}, hint: "level3_int"
        end
      end
    end
  end
end
