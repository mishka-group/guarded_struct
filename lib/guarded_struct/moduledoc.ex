defmodule GuardedStruct.Moduledoc do
  @moduledoc false

  # Keeps the @moduledoc of a module that uses GuardedStruct as the user wrote it.
  #
  # Spark's own before_compile hook adds the DSL explanation of the module's extensions to
  # its @moduledoc. GuardedStruct's extensions have no explanation, so Spark only adds empty
  # lines ("doc\n\n\n"). `capture/1` runs before Spark's hook and `restore/1` after it; the
  # doc is put back only when Spark added nothing but those empty lines, so an extension
  # that does explain itself still has its text added.

  @captured :__guarded_user_moduledoc__

  defmacro capture(env) do
    Module.put_attribute(env.module, @captured, Module.get_attribute(env.module, :moduledoc))
    nil
  end

  defmacro restore(env) do
    module = env.module
    captured = Module.get_attribute(module, @captured)
    Module.delete_attribute(module, @captured)

    case {captured, Module.get_attribute(module, :moduledoc)} do
      {{_, doc} = original, {_line, spark_doc}} when is_binary(doc) ->
        if spark_doc == doc <> "\n\n\n", do: Module.put_attribute(module, :moduledoc, original)

      _ ->
        :ok
    end

    nil
  end
end
