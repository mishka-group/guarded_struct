defmodule GuardedStructFixtures.Conditionals do
  @moduledoc """
  Nested `conditional_field` — the headline 0.1.0 unblocker.

  Two scenarios:

    * `Block` (shallow): a CMS block that can be a paragraph (string), an
      image (map), or a gallery (list of images).
    * `Document` (DEEPLY nested — see below): a page whose content is
      either plain text or a rich structure containing nested
      conditional bodies, which themselves contain conditional
      paragraphs, which in turn may contain a quote sub_field with its
      own source sub_field.

  Document's nesting depth: **7 levels** from the root, with **3 layers
  of `conditional_field`** stacked:

      Document
      └── :content (conditional)                              ← level 1
          └── sub_field :content (rich variant)               ← level 2
              └── :body (conditional)                         ← level 3
                  └── sub_field :body (structured variant)    ← level 4
                      └── :paragraphs (conditional, structs:) ← level 5
                          └── sub_field (quote paragraph)     ← level 6
                              └── sub_field :source           ← level 7

  Exercises:
    * `conditional_field` nested inside `conditional_field` ≥ 3 times
    * `structs: true` on a list-of-conditional, INSIDE a sub_field that
      is itself inside a conditional
    * `hint:` propagation through multiple nesting levels
    * Auto-numbered submodule names for sub_fields inside conditionals
      (e.g. `Document.Content1.Body1.Paragraphs1.Source`)
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

  defmodule Document do
    @moduledoc """
    Deeply-nested CMS document. See parent module's @moduledoc for the
    full nesting diagram.
    """
    use GuardedStruct

    guardedstruct do
      field(:title, String.t(), enforce: true, derives: "validate(string, not_empty)")

      # LEVEL 1 — conditional
      conditional_field(:content, any()) do
        # Variant A: plain string content
        field(:content, String.t(),
          hint: "plain",
          validator: {Validators, :is_string},
          derives: "validate(string, max_len=50_000)"
        )

        # Variant B: rich content (sub_field). LEVEL 2.
        sub_field(:content, struct(),
          hint: "rich",
          validator: {Validators, :is_map}
        ) do
          field(:title, String.t(), enforce: true, derives: "validate(string)")

          # LEVEL 3 — conditional inside the rich variant
          conditional_field(:body, any()) do
            # Variant B.1: simple-string body
            field(:body, String.t(),
              hint: "simple",
              validator: {Validators, :is_string},
              derives: "validate(string, max_len=10_000)"
            )

            # Variant B.2: structured body (sub_field). LEVEL 4.
            sub_field(:body, struct(),
              hint: "structured",
              validator: {Validators, :is_map}
            ) do
              field(:heading, String.t(), enforce: true, derives: "validate(string)")

              # LEVEL 5 — conditional list inside the structured body
              conditional_field(:paragraphs, any(),
                structs: true,
                hint: "paragraphs",
                validator: {Validators, :is_list}
              ) do
                # Variant B.2.a: plain paragraph (string)
                field(:paragraphs, String.t(),
                  hint: "plain_paragraph",
                  validator: {Validators, :is_string},
                  derives: "validate(string, max_len=5_000)"
                )

                # Variant B.2.b: quote paragraph. LEVEL 6.
                sub_field(:paragraphs, struct(),
                  hint: "quote_paragraph",
                  validator: {Validators, :is_map}
                ) do
                  field(:text, String.t(), enforce: true, derives: "validate(string)")

                  # LEVEL 7 — sub_field inside a quote paragraph
                  sub_field(:source, struct()) do
                    field(:author, String.t(), enforce: true, derives: "validate(string)")

                    field(:url, String.t(), derives: "validate(url, max_len=2048)")
                  end
                end
              end
            end
          end
        end
      end
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
