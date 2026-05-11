defmodule GuardedStructFixtures.Decorated do
  @moduledoc """
  Shows the `@derives` / `@derive_rules` decorator as a cleaner alternative
  to inline `derives:` when rules get long.

  Exercises:
    * `@derives "..."` — short canonical form
    * `@derive_rules "..."` — verbose alias
    * One-shot semantics — only the very next field-like declaration consumes
      the decorator (like `@doc`).
    * Works on `field`, `sub_field`, and `conditional_field`.
  """

  defmodule BlogPost do
    use GuardedStruct

    guardedstruct do
      @derives "sanitize(strip_tags, trim) validate(string, not_empty, max_len=200)"
      field(:title, String.t(), enforce: true)

      @derive_rules "sanitize(markdown_html, trim) validate(string, not_empty)"
      field(:body, String.t(), enforce: true)

      @derives "validate(string, max_len=50)"
      field(:slug, String.t())

      # No decorator, no inline rule — accepts anything.
      field(:draft, boolean(), default: false)

      @derives "validate(map)"
      sub_field(:metadata, struct()) do
        field(:tags, list(), default: [])
        field(:author_id, String.t(), derives: "validate(uuid)")
      end
    end
  end
end
