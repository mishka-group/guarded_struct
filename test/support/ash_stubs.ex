# Minimal stand-ins for the slice of Ash our `GuardedStruct.AshResource.Change`
# module touches at runtime. Loaded only in `Mix.env() == :test` and only when
# real Ash isn't present (which it isn't in this project — `:ash` is not a
# dep). Lets us exercise `Change.change/3` and the auto-wire transformer
# without pulling in the full Ash framework.
#
# Real Ash users get real `Ash.Changeset` and `Ash.Resource.Builder` — these
# stubs are never seen there because `Code.ensure_loaded?(Ash.Changeset)`
# returns `true` and the `unless` blocks are skipped.

unless Code.ensure_loaded?(Ash.Changeset) do
  defmodule Ash.Changeset do
    @moduledoc false
    defstruct [:resource, attributes: %{}, errors: [], changes: %{}]

    def force_change_attributes(%__MODULE__{} = cs, attrs) when is_map(attrs) do
      %{cs | changes: Map.merge(cs.changes, attrs)}
    end

    def add_error(%__MODULE__{} = cs, error) do
      %{cs | errors: cs.errors ++ [error]}
    end
  end
end

unless Code.ensure_loaded?(Ash.Resource.Change) do
  defmodule Ash.Resource.Change do
    @moduledoc false
    defmacro __using__(_opts) do
      quote do
        @behaviour Ash.Resource.Change
      end
    end

    @callback change(Ash.Changeset.t(), keyword(), map()) :: Ash.Changeset.t()
  end
end

unless Code.ensure_loaded?(Ash.Resource.Builder) do
  defmodule Ash.Resource.Builder do
    @moduledoc false
    # The auto-wire transformer runs at compile-time of the user resource —
    # potentially in a different process than the test. So we use
    # `:persistent_term` (process-independent) to record calls, scoped by
    # the resource module so each test can read its own call list.

    def add_change(dsl_state, change_module, opts) do
      module = extract_module(dsl_state)
      key = {__MODULE__, :calls, module}
      existing = :persistent_term.get(key, [])
      :persistent_term.put(key, [{change_module, opts} | existing])
      {:ok, dsl_state}
    end

    def calls(module) do
      :persistent_term.get({__MODULE__, :calls, module}, []) |> Enum.reverse()
    end

    def reset_calls(module) do
      :persistent_term.erase({__MODULE__, :calls, module})
    end

    defp extract_module(dsl_state) when is_map(dsl_state) do
      # Spark stores the target module under `:persisted.module`.
      Map.get(Map.get(dsl_state, :persist, %{}), :module) || :unknown
    end

    defp extract_module(_), do: :unknown
  end
end
