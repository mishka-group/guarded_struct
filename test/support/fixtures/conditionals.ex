defmodule GuardedStructFixtures.Conditionals do
  @moduledoc """
  Nested `conditional_field` — the headline 0.1.0 unblocker.

  Scenario: a CMS `Block` that can be a paragraph (string), an image (map),
  or a gallery (list of images, each of which is itself a string-or-map
  conditional).

  Exercises:
    * `conditional_field` nested inside `conditional_field`
    * `priority: true` short-circuit
    * `hint:` propagation
    * `structs: true` for list-of-conditional
  """

  defmodule Validators do
    @moduledoc false

    def is_string(field, value) when is_binary(value), do: {:ok, field, value}
    def is_string(field, _), do: {:error, field, "not a string"}

    def is_map(field, value) when is_map(value) and not is_struct(value),
      do: {:ok, field, value}

    def is_map(field, _), do: {:error, field, "not a map"}

    def is_list(field, value) when is_list(value), do: {:ok, field, value}
    def is_list(field, _), do: {:error, field, "not a list"}
  end

  defmodule Image do
    use GuardedStruct

    guardedstruct do
      field(:url, String.t(), enforce: true, derives: "validate(url, max_len=2048)")
      field(:alt, String.t(), default: "")
    end
  end

  defmodule Block do
    use GuardedStruct

    guardedstruct do
      conditional_field(:block, any()) do
        # 1. paragraph: just a string
        field(:block, String.t(),
          hint: "paragraph",
          validator: {Validators, :is_string},
          derives: "validate(string, max_len=10_000)"
        )

        # 2. single image: a map
        sub_field(:block, struct(),
          hint: "image",
          validator: {Validators, :is_map}
        ) do
          field(:url, String.t(), enforce: true, derives: "validate(url)")
          field(:alt, String.t(), default: "")
        end

        # 3. gallery: list of items, each is again a string-or-image
        # conditional. THIS is the nested-conditional case 0.0.x couldn't do.
        conditional_field(:block, any(),
          structs: true,
          hint: "gallery",
          validator: {Validators, :is_list}
        ) do
          field(:block, String.t(),
            hint: "gallery_item_string",
            validator: {Validators, :is_string},
            derives: "validate(string, max_len=2048)"
          )

          field(:block, struct(),
            struct: Image,
            hint: "gallery_item_image",
            validator: {Validators, :is_map}
          )
        end
      end
    end
  end
end
