defmodule GuardedStruct.AshResource.Macros do
  @moduledoc false

  # Imported by the Ash extension. Adds the forms that take options and a `do`
  # block, as `use GuardedStruct` does: `guardedstruct opts do`,
  # `sub_field name, type, opts do` and `conditional_field name, type, opts do`.

  defmacro guardedstruct(opts, do: block) when is_list(opts) do
    setters = Enum.map(opts, fn {key, value} -> {key, [], [value]} end)

    quote do
      guardedstruct do
        unquote({:__block__, [], setters ++ [block]})
      end
    end
  end

  defmacro sub_field(name, type, opts, do_block) when is_list(opts) and is_list(do_block) do
    quote do
      sub_field(unquote(name), unquote(type), unquote(opts ++ do_block))
    end
  end

  defmacro conditional_field(name, type, opts, do_block)
           when is_list(opts) and is_list(do_block) do
    quote do
      conditional_field(unquote(name), unquote(type), unquote(opts ++ do_block))
    end
  end
end
