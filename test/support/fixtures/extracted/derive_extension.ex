defmodule GuardedStructTest.Fixtures.DeriveExtension.SlugDerives do
  use GuardedStruct.Derive.Extension

  derives do
    validator :my_slug, fn input ->
      is_binary(input) and Regex.match?(~r/^[a-z0-9-]+$/, input)
    end

    sanitizer :slugify, fn input when is_binary(input) ->
      input
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9-]+/u, "-")
      |> String.trim("-")
    end
  end
end

defmodule GuardedStructTest.Fixtures.DeriveExtension.WithSlug do
  use GuardedStruct

  guardedstruct do
    field :my_slug, String.t(), derives: "validate(my_slug)"
  end
end

defmodule GuardedStructTest.Fixtures.DeriveExtension.WithSlugify do
  use GuardedStruct

  guardedstruct do
    field :my_slug, String.t(), derives: "sanitize(slugify) validate(my_slug)"
  end
end
