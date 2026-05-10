defmodule GuardedStruct.Transformers.GenerateBuilder do
  @moduledoc false

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer
  alias GuardedStruct.Transformers.Codegen

  @impl true
  def transform(dsl_state) do
    entities = Transformer.get_entities(dsl_state, [:guardedstruct])

    block_enforce = Transformer.get_option(dsl_state, [:guardedstruct], :enforce, false)
    opaque? = Transformer.get_option(dsl_state, [:guardedstruct], :opaque, false)
    error? = Transformer.get_option(dsl_state, [:guardedstruct], :error, false)
    module_opt = Transformer.get_option(dsl_state, [:guardedstruct], :module)

    Codegen.validate_entities!(entities)

    section_options = %{
      authorized_fields:
        Transformer.get_option(dsl_state, [:guardedstruct], :authorized_fields, false),
      jason: Transformer.get_option(dsl_state, [:guardedstruct], :jason, false)
    }

    body =
      Codegen.build_body(entities, block_enforce, opaque?, error?, [], section_options)

    injected =
      case module_opt do
        nil ->
          body

        mod_ast ->
          quote do
            defmodule unquote(mod_ast) do
              unquote(body)
            end
          end
      end

    {:ok, Transformer.eval(dsl_state, [], injected)}
  end
end
