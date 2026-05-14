defmodule GuardedStruct.Derive.Extension.Dsl do
  @moduledoc false

  alias GuardedStruct.Derive.Extension.Dsl.{Validator, Sanitizer}

  @validator %Spark.Dsl.Entity{
    name: :validator,
    target: Validator,
    args: [:name, :fun],
    describe: """
    Declare a custom validator op callable as `validate(<name>)` from
    any GuardedStruct module that has this extension wired in.
    """,
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "Op name. Used as `validate(<name>)` in derive strings."
      ],
      fun: [
        type: :quoted,
        required: true,
        doc: """
        Single-arg function. Return value semantics:

          * `true` — input passes
          * `false` — input fails (default error message)
          * `{:error, field, action, message}` — explicit error
          * any other value — used as the validated (coerced) output
        """
      ]
    ]
  }

  @sanitizer %Spark.Dsl.Entity{
    name: :sanitizer,
    target: Sanitizer,
    args: [:name, :fun],
    describe: """
    Declare a custom sanitizer op callable as `sanitize(<name>)`. Runs
    before validation in the derive pipeline; the return value replaces
    the input.
    """,
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "Op name. Used as `sanitize(<name>)` in derive strings."
      ],
      fun: [
        type: :quoted,
        required: true,
        doc: "Single-arg function. Return value replaces the input."
      ]
    ]
  }

  @section %Spark.Dsl.Section{
    name: :derives,
    describe: """
    Container for custom validator and sanitizer ops.

    ## Example

        defmodule MyApp.Derives do
          use GuardedStruct.Derive.Extension

          derives do
            validator :slug, fn input ->
              is_binary(input) and Regex.match?(~r/^[a-z0-9-]+$/, input)
            end

            sanitizer :slugify, fn input when is_binary(input) ->
              input |> String.downcase() |> String.replace(~r/[^a-z0-9-]+/u, "-")
            end
          end
        end
    """,
    entities: [@validator, @sanitizer]
  }

  use Spark.Dsl.Extension,
    sections: [@section],
    transformers: [GuardedStruct.Derive.Extension.Transformers.Codegen]
end
