defmodule GuardedStructFixtures.Dynamic do
  @moduledoc """
  Free-form / runtime-extensible keys.

  Exercises:
    * `dynamic_field` — open-shape metadata map
    * Pattern-keyed map (regex `field` name) — typed shards with string keys
    * Composing a pattern-keyed map module into a regular `struct:` reference
  """

  defmodule Shard do
    use GuardedStruct

    guardedstruct do
      field(:node, String.t(), enforce: true, derives: "validate(ipv4)")
      field(:replicas, integer(), default: 1, derives: "validate(integer)")
    end
  end

  defmodule ShardsMap do
    @moduledoc "Pattern-keyed map — keys must match the regex, values are `%Shard{}`."
    use GuardedStruct

    guardedstruct do
      field(~r/^shard_\d+$/, struct(),
        struct: Shard,
        derives: "validate(map, not_empty)"
      )
    end
  end

  defmodule Document do
    @moduledoc "Document with id, body, and an open metadata map."
    use GuardedStruct

    guardedstruct do
      field(:id, String.t(), enforce: true, derives: "validate(uuid)")
      field(:body, String.t(), enforce: true, derives: "validate(string)")
      dynamic_field(:metadata)
    end
  end

  defmodule ClusterPlan do
    @moduledoc "Composes the pattern-map (ShardsMap) with regular fields."
    use GuardedStruct

    guardedstruct do
      field(:status, String.t(),
        enforce: true,
        derives: "validate(enum=String[draft::active::archived])"
      )

      field(:shards, struct(), enforce: true, struct: ShardsMap)
    end
  end

  defmodule Envelope do
    @moduledoc "dynamic_field below the top level: nested and list sub_field, struct: reference, conditional."
    use GuardedStruct

    guardedstruct do
      field(:meta, map())
      dynamic_field(:top_meta)

      sub_field(:account, struct()) do
        field(:email, String.t())
        dynamic_field(:meta)

        sub_field(:settings, struct()) do
          field(:theme, String.t())
          dynamic_field(:prefs)
        end
      end

      sub_field(:events, list(struct()), structs: true) do
        field(:name, String.t())
        dynamic_field(:payload)
      end

      field(:document, struct(), struct: Document)

      conditional_field(:attachment, any()) do
        field(:attachment, String.t(), hint: "url", derives: "validate(string)")

        sub_field(:attachment, struct(), hint: "inline") do
          field(:kind, String.t())
          dynamic_field(:data)
        end
      end
    end
  end
end
