defmodule GuardedStruct.Info do
  @moduledoc """
  Runtime introspection of guardedstruct DSL state.

  Standard Spark idiom — `use Spark.InfoGenerator` produces typed accessors
  for every section + option in the DSL.

  ## Examples

      defmodule MyApp.User do
        use GuardedStruct

        guardedstruct enforce: true do
          field :name, :string
          field :age, :integer
        end
      end

      GuardedStruct.Info.guardedstruct(MyApp.User)
      #=> [%GuardedStruct.Dsl.Field{name: :name, ...}, ...]

      GuardedStruct.Info.guardedstruct_enforce!(MyApp.User)
      #=> true

      GuardedStruct.Info.guardedstruct_module!(MyApp.User)
      #=> nil   # only set if `module: SubName` was used

  In addition to the auto-generated Spark accessors, this module exposes
  a few convenience helpers (`fields/1`, `enforce_keys/1`, etc.) that
  pre-derived field metadata for callers that don't want to walk entities
  themselves.
  """

  use Spark.InfoGenerator,
    extension: GuardedStruct.Dsl,
    sections: [:guardedstruct]

  @doc """
  Return the user-declared field, sub_field, and conditional_field names
  in declaration order.
  """
  def fields(module) do
    module
    |> guardedstruct()
    |> Enum.map(& &1.name)
    |> Enum.uniq()
  end

  @doc """
  Return the list of enforced field names.
  """
  def enforce_keys(module), do: module.enforce_keys()

  @doc """
  Return the runtime field metadata (the same shape stored on every
  generated module under `__fields__/0`).
  """
  def fields_meta(module), do: module.__fields__()

  @doc """
  Return the field metadata for a single name, or `nil` if absent.
  """
  def field(module, name) when is_atom(name) do
    Enum.find(module.__fields__(), &(&1.name == name))
  end

  @doc """
  True if the field exists.
  """
  def field?(module, name) when is_atom(name) do
    name in module.keys()
  end
end
