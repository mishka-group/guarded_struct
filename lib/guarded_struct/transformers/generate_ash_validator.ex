defmodule GuardedStruct.Transformers.GenerateAshValidator do
  @moduledoc false

  # Codegen for the `GuardedStruct.AshResource` extension. Mirrors
  # `GuardedStruct.Transformers.GenerateBuilder` but emits
  # `__guarded_change__/1` and `__guarded_fields__/0` (plus the runtime
  # metadata accessor `__guarded_information__/0`) instead of `defstruct`
  # + `builder/2`.
  #
  # The function is called `__guarded_change__` (not `__guarded_validate__`)
  # because it can both *validate* AND *transform* values — sanitize ops
  # trim/downcase/slugify, derive auto-fills, etc. "Change" matches Ash's
  # terminology (the function fires inside an `Ash.Resource.Change`).
  #
  # Function names are namespaced with `__guarded_*` so they don't collide
  # with Ash's `__resource__/1`, `__struct__/1`, etc. Code that needs them
  # imports the `GuardedStruct.AshResource.Info` module.

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer
  alias GuardedStruct.Dsl.ConditionalField
  alias GuardedStruct.Transformers.Codegen

  @impl true
  def transform(dsl_state) do
    entities = Transformer.get_entities(dsl_state, [:guardedstruct])

    block_enforce = Transformer.get_option(dsl_state, [:guardedstruct], :enforce, false)

    Codegen.validate_entities!(entities)

    section_options = %{
      authorized_fields:
        Transformer.get_option(dsl_state, [:guardedstruct], :authorized_fields, false)
    }

    {keys, _defstruct_kw, _types, enforce_keys, fields_runtime} =
      Codegen.struct_pieces(entities, block_enforce)

    conditional_keys =
      entities
      |> Enum.filter(&match?(%ConditionalField{}, &1))
      |> Enum.map(& &1.name)
      |> Enum.uniq()

    info_map =
      Macro.escape(%{
        path: [],
        key: :root,
        keys: keys,
        enforce_keys: enforce_keys,
        conditional_keys: conditional_keys,
        options: section_options
      })

    body =
      quote do
        if Module.defines?(__MODULE__, {:__guarded_information__, 0}, :def),
          do: defoverridable(__guarded_information__: 0)

        if Module.defines?(__MODULE__, {:__guarded_fields__, 0}, :def),
          do: defoverridable(__guarded_fields__: 0)

        if Module.defines?(__MODULE__, {:__guarded_change__, 1}, :def),
          do: defoverridable(__guarded_change__: 1)

        if Module.defines?(__MODULE__, {:__guarded_change__, 2}, :def),
          do: defoverridable(__guarded_change__: 2)

        def __guarded_information__ do
          Map.put(unquote(info_map), :module, __MODULE__)
        end

        def __guarded_fields__, do: unquote(Macro.escape(fields_runtime))

        @doc """
        Apply the full GuardedStruct pipeline (sanitize → validate → derive →
        main_validator) to `attrs` and return either `{:ok, transformed_attrs}`
        or `{:error, errors}`. Wire this into an `Ash.Resource.Change` to plug
        guardedstruct rules into Ash's changeset pipeline.

        The function is named `__guarded_change__` because it does more than
        validate — it can also transform values (trim, downcase, slugify,
        auto-fill, etc.) before they reach the data layer.
        """
        def __guarded_change__(attrs, error? \\ false) do
          GuardedStruct.Runtime.validate(__MODULE__, attrs, error?)
        end
      end

    {:ok, Transformer.eval(dsl_state, [], body)}
  end
end
