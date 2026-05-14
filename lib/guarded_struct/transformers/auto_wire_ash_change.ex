defmodule GuardedStruct.Transformers.AutoWireAshChange do
  @moduledoc false

  # Injects `GuardedStruct.AshResource.Change` into the resource's
  # top-level `changes` section when `auto_wire: true` is set on the
  # guardedstruct section. Equivalent to writing
  # `changes do change GuardedStruct.AshResource.Change end` by hand.

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
        {:ok, dsl_state}

      true ->
        apply(Ash.Resource.Builder, :add_change, [
          dsl_state,
          GuardedStruct.AshResource.Change,
          []
        ])
    end
  end
end
