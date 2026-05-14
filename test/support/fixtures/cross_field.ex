defmodule GuardedStructFixtures.CrossField do
  @moduledoc """
  Cross-field dependencies via three of the four core keys.

  Exercises:
    * `from:` — pull a value from elsewhere in the input map
    * `on:`   — require another field/path to be present
    * `auto:` — compute a value at build time
    * `domain:` — constrain this field's allowed values based on a sibling field
    * **`sub_field(..., enforce: true)` enforce-cascade pattern** — see
      `StrictEvent` below

  See `test/core_keys_test.exs` for richer `domain:` coverage; here we
  use a minimal sibling-path domain to keep the fixture realistic.
  """

  defmodule AuditedEvent do
    use GuardedStruct

    guardedstruct authorized_fields: true do
      # Top-level metadata
      field(:actor_id, String.t(), enforce: true, derives: "validate(uuid)")

      field(:account_type, String.t(),
        enforce: true,
        derives: "validate(enum=String[free::pro::enterprise])"
      )

      # `domain:` here looks at the sibling `event.kind` (note: dot-separated
      # path resolved against the same full_attrs map). Only allowed when
      # account_type is in the listed enum AND the event kind is one of the
      # safe ones — i.e. expresses an authorization rule.
      field(:requested_by, String.t(),
        domain: "!account_type=String[free, pro, enterprise]",
        derives: "validate(string, not_empty)"
      )

      sub_field(:event, struct()) do
        # `from:` pulls actor_id from the parent so the event carries the
        # actor identity without the caller having to wire it twice.
        field(:actor_id, String.t(), enforce: false, from: "root::actor_id")

        # `auto:` mints a fresh event UUID at build time.
        field(:event_id, String.t(),
          enforce: false,
          auto: {GuardedStructTest.Support.UUID, :generate}
        )

        # `on:` enforces that the parent path exists before we accept :name.
        field(:name, String.t(),
          enforce: true,
          on: "root::actor_id",
          derives: "validate(string, not_empty)"
        )

        field(:kind, String.t(),
          enforce: true,
          derives: "validate(enum=String[login::logout::data.read::billing.refund])"
        )
      end
    end
  end

  defmodule StrictEvent do
    @moduledoc """
    Demonstrates the **enforce-cascade pattern** for sub_field.

    When a `sub_field` is declared with `enforce: true`, two things happen
    at compile time (see `generate_sub_field_modules.ex:74`):

      1. The sub_field itself becomes required in the parent.
      2. The sub_field's submodule is generated with `block_enforce = true`,
         so **every inner field without an explicit `default:` becomes
         required automatically**.

    To opt an inner field OUT of the cascade, mark it `enforce: false`
    explicitly (see `:trace_id` below) or give it a `default:` value.
    """
    use GuardedStruct

    guardedstruct do
      field(:source, String.t(), enforce: true, derives: "validate(string, not_empty)")

      # enforce: true on the sub_field cascades to inner fields without defaults
      sub_field(:payload, struct(), enforce: true) do
        # Implicitly enforced via the cascade (no `enforce:` opt, no `default:`)
        field(:kind, String.t(), derives: "validate(string)")

        # Also implicitly enforced via the cascade
        field(:body, map(), derives: "validate(map)")

        # Has a default → NOT enforced even though parent has enforce: true
        field(:retries, integer(), default: 0, derives: "validate(integer)")

        # Explicitly opted OUT of the cascade
        field(:trace_id, String.t(), enforce: false, derives: "validate(string)")
      end
    end
  end
end
