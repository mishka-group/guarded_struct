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

    virtual_keys =
      fields_runtime |> Enum.filter(&(&1.kind == :virtual_field)) |> Enum.map(& &1.name)

    dynamic_keys =
      fields_runtime |> Enum.filter(&(&1.kind == :dynamic_field)) |> Enum.map(& &1.name)

    info_map =
      Macro.escape(%{
        path: [],
        key: :root,
        keys: keys,
        enforce_keys: enforce_keys,
        conditional_keys: conditional_keys,
        virtual_keys: virtual_keys,
        dynamic_keys: dynamic_keys,
        options: section_options
      })

    field_name_set =
      fields_runtime
      |> Enum.map(& &1.name)
      |> MapSet.new()
      |> Macro.escape()

    field_meta_map =
      fields_runtime
      |> Map.new(fn m -> {m.name, m} end)
      |> Macro.escape()

    body =
      quote do
        if Module.defines?(__MODULE__, {:__guarded_information__, 0}, :def),
          do: defoverridable(__guarded_information__: 0)

        if Module.defines?(__MODULE__, {:__guarded_fields__, 0}, :def),
          do: defoverridable(__guarded_fields__: 0)

        if Module.defines?(__MODULE__, {:__guarded_field_name_set__, 0}, :def),
          do: defoverridable(__guarded_field_name_set__: 0)

        if Module.defines?(__MODULE__, {:__guarded_change__, 1}, :def),
          do: defoverridable(__guarded_change__: 1)

        if Module.defines?(__MODULE__, {:__guarded_change__, 2}, :def),
          do: defoverridable(__guarded_change__: 2)

        def __guarded_information__ do
          Map.put(unquote(info_map), :module, __MODULE__)
        end

        def __guarded_fields__, do: unquote(Macro.escape(fields_runtime))

        @doc """
        Compile-time-baked `MapSet` of every field name owned by the
        `guardedstruct` block. Used by `GuardedStruct.AshResource.Change`
        to decide, in O(1), whether a key in `changeset.atomics`
        belongs to the pipeline.
        """
        def __guarded_field_name_set__, do: unquote(field_name_set)

        @doc """
        O(1) lookup of a field's compile-time metadata by name. Returns
        `nil` for unknown fields.
        """
        def __guarded_field_meta__(name), do: Map.get(unquote(field_meta_map), name)

        def __field_meta__(name), do: __guarded_field_meta__(name)

        @__guarded_has_validator__ Module.defines?(__MODULE__, {:validator, 2}, :def)
        def __guarded_has_validator__, do: @__guarded_has_validator__

        @__guarded_has_main_validator__ Module.defines?(__MODULE__, {:main_validator, 1}, :def)
        def __guarded_has_main_validator__, do: @__guarded_has_main_validator__

        unless Module.defines?(__MODULE__, {:__guarded_derive_extensions_opt__, 0}, :def) do
          def __guarded_derive_extensions_opt__, do: nil
        end

        def __guarded_error_module__, do: nil

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
