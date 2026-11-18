defmodule GuardedStructTest.Fixtures.TypedocUses.Items do
  @moduledoc "The user's own item module, in another file."
  use GuardedStruct

  @typedoc "One item, as the user describes it."
  guardedstruct do
    field :sku, String.t(), enforce: true
  end
end
