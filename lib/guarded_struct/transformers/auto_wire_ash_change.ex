defmodule GuardedStruct.Transformers.AutoWireAshChange do
  @moduledoc false

  # Injects `GuardedStruct.AshResource.Change` into the resource's top-level
  # `changes` section when the user has set `auto_wire: true` on the
  # `guardedstruct` section. Equivalent to the user writing
  # `changes do change GuardedStruct.AshResource.Change end` by hand.
  #
  # No-op in three cases:
  #   1. `auto_wire: false` (the default) — explicit-wiring mode.
  #   2. Ash isn't compiled in the project — guarded by Code.ensure_loaded?.
  #   3. This transformer is somehow running outside the AshResource extension
  #      (e.g. plain `use GuardedStruct`) — the flag is silently ignored.

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def after?(GuardedStruct.Transformers.GenerateAshValidator), do: true
  def after?(_), do: false

  @impl true
  def transform(dsl_state) do
    auto_wire? = Transformer.get_option(dsl_state, [:guardedstruct], :auto_wire, false) == true

    cond do
      not auto_wire? ->
        {:ok, dsl_state}

      not Code.ensure_loaded?(Ash.Resource.Builder) ->
        # `auto_wire: true` was set but Ash isn't present. Silently skip:
        # the standalone `use GuardedStruct` flow also routes through this
        # extension list in some setups, and we don't want to crash there.
        {:ok, dsl_state}

      true ->
        # Add a top-level `change GuardedStruct.AshResource.Change` entry.
        # Ash applies it on `:create` and `:update` by default (see the
        # `on:` option in `Ash.Resource.Change.schema/0`).
        #
        # Dispatched via `apply/3` so the compiler doesn't reference
        # `Ash.Resource.Builder` at compile time — that would emit
        # "module not available" warnings on projects without `:ash`.
        apply(Ash.Resource.Builder, :add_change, [
          dsl_state,
          GuardedStruct.AshResource.Change,
          []
        ])
    end
  end
end
