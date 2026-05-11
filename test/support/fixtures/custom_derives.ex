defmodule GuardedStructFixtures.CustomDerives do
  @moduledoc """
  Custom validators / sanitizers via the Spark-native extension DSL.

  Exercises:
    * `use GuardedStruct.Derive.Extension`
    * `validator :name, fun` — declarative validator op
    * `sanitizer :name, fun` — declarative sanitizer op that transforms input
    * Composing two custom ops on one field: `sanitize(slugify) validate(slug)`

  Activated by `:derive_extensions` config; see `test/fixtures_test.exs`
  for the wiring.
  """

  defmodule MyDerives do
    use GuardedStruct.Derive.Extension

    validator(:slug, fn input ->
      is_binary(input) and Regex.match?(~r/^[a-z0-9][a-z0-9-]*$/, input)
    end)

    validator(:positive_int, fn input -> is_integer(input) and input > 0 end)

    sanitizer(:slugify, fn input when is_binary(input) ->
      input
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")
    end)
  end

  defmodule Article do
    use GuardedStruct

    guardedstruct do
      field(:title, String.t(), enforce: true, derives: "validate(string, not_empty)")

      # Composed custom ops:
      field(:slug, String.t(),
        enforce: true,
        derives: "sanitize(slugify) validate(slug)"
      )

      field(:views, integer(), default: 1, derives: "validate(positive_int)")
    end
  end
end
