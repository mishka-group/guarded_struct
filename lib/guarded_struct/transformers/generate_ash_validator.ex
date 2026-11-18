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

  alias GuardedStruct.Transformers.Codegen
  alias Spark.Dsl.Transformer

  @impl true
  def transform(dsl_state) do
    entities = Transformer.get_entities(dsl_state, [:guardedstruct])

    block_enforce = Transformer.get_option(dsl_state, [:guardedstruct], :enforce, false)

    Codegen.validate_entities!(entities)

    section_options =
      Codegen.declared_options(%{
        authorized_fields:
          Transformer.get_option(dsl_state, [:guardedstruct], :authorized_fields, false),
        main_validator: Transformer.get_option(dsl_state, [:guardedstruct], :main_validator),
        validate_derive: Transformer.get_option(dsl_state, [:guardedstruct], :validate_derive),
        sanitize_derive: Transformer.get_option(dsl_state, [:guardedstruct], :sanitize_derive)
      })

    {keys, _defstruct_kw, _types, enforce_keys, fields_runtime} =
      Codegen.struct_pieces(entities, block_enforce)

    info_map =
      %{
        path: [],
        key: :root,
        keys: keys,
        enforce_keys: enforce_keys,
        options: section_options
      }
      |> Map.merge(Codegen.info_keys(entities, fields_runtime))
      |> Macro.escape()

    body =
      quote do
        unquote(
          Codegen.overridable_ast(
            __guarded_information__: 0,
            __guarded_fields__: 0,
            __guarded_field_name_set__: 0,
            __guarded_change__: 1,
            __guarded_change__: 2
          )
        )

        unquote(fields_ast(info_map, fields_runtime, keys))
        unquote(Codegen.validator_flags_ast())
        unquote(change_ast())
      end

    {:ok, Transformer.eval(dsl_state, [], body)}
  end

  defp fields_ast(info_map, fields_runtime, keys) do
    field_name_set =
      fields_runtime
      |> Enum.map(& &1.name)
      |> MapSet.new()
      |> Macro.escape()

    quote do
      def __guarded_information__ do
        Map.put(unquote(info_map), :module, __MODULE__)
      end

      @__guarded_fields__ GuardedStruct.Transformers.Codegen.bake_child_modules(
                            unquote(Macro.escape(fields_runtime)),
                            __MODULE__
                          )
      def __guarded_fields__, do: @__guarded_fields__

      def __guarded_atom_lookup__, do: unquote(Macro.escape(Codegen.atom_lookup_for(keys)))

      @doc """
      Compile-time-baked `MapSet` of every field name owned by the
      `guardedstruct` block. Used by `GuardedStruct.AshResource.Change`
      to decide, in O(1), whether a key in `changeset.atomics`
      belongs to the pipeline.
      """
      def __guarded_field_name_set__, do: unquote(field_name_set)

      @__guarded_field_meta_map__ Map.new(@__guarded_fields__, fn m -> {m.name, m} end)

      @doc """
      O(1) lookup of a field's compile-time metadata by name. Returns
      `nil` for unknown fields.
      """
      def __guarded_field_meta__(name), do: Map.get(@__guarded_field_meta_map__, name)

      def __field_meta__(name), do: __guarded_field_meta__(name)
    end
  end

  defp change_ast do
    quote do
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
  end
end
