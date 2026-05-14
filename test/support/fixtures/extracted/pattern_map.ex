defmodule GuardedStructTest.Fixtures.PatternMap.Shard do
  use GuardedStruct

  guardedstruct do
    field :node, String.t(), enforce: true, derives: "sanitize(trim) validate(ipv4)"
  end
end

defmodule GuardedStructTest.Fixtures.PatternMap.ShardsMap do
  use GuardedStruct

  guardedstruct do
    field ~r/^shard_\d+$/,
          struct(),
          struct: GuardedStructTest.Fixtures.PatternMap.Shard,
          derives: "validate(map, not_empty)"
  end
end

defmodule GuardedStructTest.Fixtures.PatternMap.Plan do
  use GuardedStruct

  guardedstruct do
    field :status, String.t(), enforce: true

    field :shards_map,
          struct(),
          struct: GuardedStructTest.Fixtures.PatternMap.ShardsMap,
          enforce: true
  end
end

defmodule GuardedStructTest.Fixtures.PatternMap.MultiPattern do
  use GuardedStruct

  guardedstruct do
    field ~r/^shard_\d+$/, struct(), struct: GuardedStructTest.Fixtures.PatternMap.Shard
    field ~r/^backup_\d+$/, struct(), struct: GuardedStructTest.Fixtures.PatternMap.Shard
  end
end

defmodule GuardedStructTest.Fixtures.PatternMap.HeadersMap do
  use GuardedStruct

  guardedstruct do
    field ~r/^X-[A-Z][A-Za-z0-9\-]*$/, String.t()
  end
end
