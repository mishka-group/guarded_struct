# GuardedStruct

The creation of this macro will allow you to build `Structs` that provide you with a number of important options, including the following:

1. Validation
2. Sanitizing
3. Constructor
4. It provides the capacity to operate in a nested style simultaneously.

## Example:

```elixir
defmodule ConditionalFieldComplexTest do
  use GuardedStruct
  alias ConditionalFieldValidatorTestValidators, as: VAL

  guardedstruct do
    field(:provider, String.t())

    sub_field(:profile, struct()) do
      field(:name, String.t(), enforce: true)
      field(:family, String.t(), enforce: true)

      conditional_field(:address, any()) do
        field(:address, String.t(), hint: "address1", validator: {VAL, :is_string_data})

        sub_field(:address, struct(), hint: "address2", validator: {VAL, :is_map_data}) do
          field(:location, String.t(), enforce: true)
          field(:text_location, String.t(), enforce: true)
        end

        sub_field(:address, struct(), hint: "address3", validator: {VAL, :is_map_data}) do
          field(:location, String.t(), enforce: true, derive: "validate(string, location)")
          field(:text_location, String.t(), enforce: true)
          field(:email, String.t(), enforce: true)
        end
      end
    end

    conditional_field(:product, any()) do
      field(:product, String.t(), hint: "product1", validator: {VAL, :is_string_data})

      sub_field(:product, struct(), hint: "product2", validator: {VAL, :is_map_data}) do
        field(:name, String.t(), enforce: true)
        field(:price, integer(), enforce: true)

        sub_field(:information, struct()) do
          field(:creator, String.t(), enforce: true)
          field(:company, String.t(), enforce: true)

          conditional_field(:inventory, integer() | struct(), enforce: true) do
            field(:inventory, integer(),
              hint: "inventory1",
              validator: {VAL, :is_int_data},
              derive: "validate(integer, max_len=33)"
            )

            sub_field(:inventory, struct(), hint: "inventory2", validator: {VAL, :is_map_data}) do
              field(:count, integer(), enforce: true)
              field(:expiration, integer(), enforce: true)
            end
          end
        end
      end
    end
  end
end
```


Suppose you are going to collect a number of pieces of information from the user, and before doing anything else, you are going to sanitize them.
After that, you are going to validate each piece of data, and if there are no issues, you will either display it in a proper output or save it somewhere else.
All of the characteristics that are associated with this macro revolve around cleaning and validating the data.

The features that we list below are individually based on a particular strategy and requirement, but thankfully, they may be combined and mixed in any way that you see fit.

It bestows to you a significant amount of authority in this sphere.
After the initial version of this macro was obtained from the source of the `typed_struct` library, many sections of it were rewritten, or new concepts were taken from libraries in Rust and Scala and added to this library in the form of Elixir base.

The initial version of this macro can be found in the `typed_struct` library. Its base is a syntax that is very easy to comprehend, especially for non-technical product managers, and highly straightforward.

Before explaining the copyright, I must point out that the primary library, which is `typed_struct`, is no longer supported for a long time, so please pay attention to the following copyright.

[![Run in Livebook](https://livebook.dev/badge/v1/pink.svg)](https://livebook.dev/run?url=https%3A%2F%2Fgithub.com%2Fmishka-group%2Fguarded_struct%2Fblob%2Fmaster%2Fguidance%2Fguarded-struct.livemd)

## Installation

```elixir
def deps do
  [
    {:guarded_struct, "~> 0.0.1"}
  ]
end
```

## Table of Contents

* [Defines a guarded struct](https://github.com/mishka-group/guarded_struct/blob/master/guidance/guarded-struct.md#defines-a-guarded-struct)
* [Defining a struct layer without additional options](https://github.com/mishka-group/guarded_struct/blob/master/guidance/guarded-struct.md#defining-a-struct-layer-without-additional-options)
* [Define a struct with settings related to essential keys or `opaque` type](https://github.com/mishka-group/guarded_struct/blob/master/guidance/guarded-struct.md#define-a-struct-with-settings-related-to-essential-keys-or-opaque-type)
* [Defining the struct by calling the validation module or calling from the module that contains the struct](https://github.com/mishka-group/guarded_struct/blob/master/guidance/guarded-struct.md#defining-the-struct-by-calling-the-validation-module-or-calling-from-the-module-that-contains-the-struct)
* [Define the struct by calling the `main_validator` for full access on the output](https://github.com/mishka-group/guarded_struct/blob/master/guidance/guarded-struct.md#define-the-struct-by-calling-the-main_validator-for-full-access-on-the-output)
* [Define struct with `derive`](https://github.com/mishka-group/guarded_struct/blob/master/guidance/guarded-struct.md#define-struct-with-derive)
* [Extending `derive` section](https://github.com/mishka-group/guarded_struct/blob/master/guidance/guarded-struct.md#extending-derive-section)
* [Struct definition with `validator` and `derive` simultaneously](https://github.com/mishka-group/guarded_struct/blob/master/guidance/guarded-struct.md#struct-definition-with-validator-and-derive-simultaneously)
* [Define a nested and complex struct](https://github.com/mishka-group/guarded_struct/blob/master/guidance/guarded-struct.md#define-a-nested-and-complex-struct)
* [Error and data output sample](https://github.com/mishka-group/guarded_struct/blob/master/guidance/guarded-struct.md#error-and-data-output-sample)
* [Set config to show error inside `defexception`](https://github.com/mishka-group/guarded_struct/blob/master/guidance/guarded-struct.md#error-and-data-output-sample)
* [Error `defexception` modules](https://github.com/mishka-group/guarded_struct/blob/master/guidance/guarded-struct.md#error-defexception-modules)
* [`authorized_fields` option to limit user input](https://github.com/mishka-group/guarded_struct/blob/master/guidance/guarded-struct.md#authorized_fields-option-to-limit-user-input)
* [List of structs](https://github.com/mishka-group/guarded_struct/blob/master/guidance/guarded-struct.md#list-of-structs)
* [Struct information function](https://github.com/mishka-group/guarded_struct/blob/master/guidance/guarded-struct.md#struct-information-function)
* [Transmitting whole output of builder function to its children](https://github.com/mishka-group/guarded_struct/blob/master/guidance/guarded-struct.md#transmitting-whole-output-of-builder-function-to-its-children)
* [Auto core key](https://github.com/mishka-group/guarded_struct/blob/master/guidance/guarded-struct.md#auto-core-key)
* [On core key](https://github.com/mishka-group/guarded_struct/blob/master/guidance/guarded-struct.md#on-core-key)
* [From core key](https://github.com/mishka-group/guarded_struct/blob/master/guidance/guarded-struct.md#from-core-key)
* [Domain core key](https://github.com/mishka-group/guarded_struct/blob/master/guidance/guarded-struct.md#domain-core-key)
* [Domain core key with `equal` and `either` support](https://github.com/mishka-group/guarded_struct/blob/master/guidance/guarded-struct.md#domain-core-key-with-equal-and-either-support)
* [Domain core key with Custom function support](https://github.com/mishka-group/guarded_struct/blob/master/guidance/guarded-struct.md#domain-core-key-with-custom-function-support)
* [Conditional fields](https://github.com/mishka-group/guarded_struct/blob/master/guidance/guarded-struct.md#conditional-fields)
* [List Conditional fields](https://github.com/mishka-group/guarded_struct/blob/master/guidance/guarded-struct.md#list-conditional-fields)



The docs can be found at https://hexdocs.pm/guarded_struct.
