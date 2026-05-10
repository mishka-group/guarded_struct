defmodule GuardedStruct.AshResource.Info do
  @moduledoc """
  Runtime introspection for the `GuardedStruct.AshResource` extension.

  Same shape as `GuardedStruct.Info` but reads from the `__guarded_*`
  namespaced functions the Ash extension generates (so it doesn't
  collide with Ash's own `Ash.Resource.Info` callbacks).

  ## Example

      defmodule MyApp.User do
        use Ash.Resource,
          domain: MyApp.MyDomain,
          extensions: [GuardedStruct.AshResource]

        guardedstruct do
          field :nickname, :string, derives: "validate(string, max_len=20)"
        end
      end

      GuardedStruct.AshResource.Info.fields(MyApp.User)
      #=> [:nickname]

      GuardedStruct.AshResource.Info.field(MyApp.User, :nickname)
      #=> %{kind: :field, name: :nickname, derives: "validate(string, max_len=20)", ...}
  """

  use Spark.InfoGenerator,
    extension: GuardedStruct.AshResource,
    sections: [:guardedstruct]

  @doc """
  Return field, sub_field, and conditional_field names in declaration order.
  """
  def fields(module) do
    module
    |> guardedstruct()
    |> Enum.map(& &1.name)
    |> Enum.uniq()
  end

  @doc """
  Return the runtime field metadata stored under `__guarded_fields__/0`.
  """
  def fields_meta(module), do: module.__guarded_fields__()

  @doc """
  Return metadata for a single field name, or `nil`.
  """
  def field(module, name) when is_atom(name) do
    Enum.find(module.__guarded_fields__(), &(&1.name == name))
  end

  @doc """
  True if a guardedstruct-declared field exists with this name.
  """
  def field?(module, name) when is_atom(name) do
    Enum.any?(module.__guarded_fields__(), &(&1.name == name))
  end

  @doc """
  Return the full information map (path, keys, enforce_keys, options, etc.).
  """
  def information(module), do: module.__guarded_information__()

  @doc """
  Run the validation pipeline on `attrs` and return `{:ok, validated_map}`
  or `{:error, errors}`. Convenience wrapper over the resource's own
  `__guarded_validate__/1`.
  """
  def validate(module, attrs, error? \\ false) do
    module.__guarded_validate__(attrs, error?)
  end
end
