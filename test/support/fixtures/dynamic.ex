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
end
