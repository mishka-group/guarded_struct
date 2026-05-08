defmodule GuardedStruct do
  @moduledoc """
  GuardedStruct macro: build structs with validation, sanitization, constructors,
  and nested-struct support.

  Phase-1 Spark rewrite. Public API kept stable with the legacy `0.0.x` line.

  ## Quick example

      defmodule MyStruct do
        use GuardedStruct

        guardedstruct enforce: true do
          field :name, String.t()
          field :title, String.t(), default: "untitled"
        end
      end

      MyStruct.builder(%{name: "Mishka"})
      # => {:ok, %MyStruct{name: "Mishka", title: "untitled"}}

  See `REDESIGN.md` at the project root for the full design and the migration
  story from the legacy macro core.
  """

  use Spark.Dsl, default_extensions: [extensions: [GuardedStruct.Dsl]]

  # Auto-import our `guardedstruct/1` and `guardedstruct/2` wrappers into the
  # consumer module. The arity-1 wrapper validates the AST and delegates to
  # Spark's auto-generated section macro at `GuardedStruct.Dsl.guardedstruct/1`.
  # The arity-2 wrapper additionally lifts top-level options (`enforce:`,
  # `module:`, etc.) into schema-option setter calls inside the section body.
  defmacro __using__(opts) do
    super_ast = super(opts)

    quote do
      unquote(super_ast)
      # Stop Spark's auto-imported guardedstruct/1 from shadowing ours.
      import GuardedStruct.Dsl, only: []
      import GuardedStruct, only: [guardedstruct: 1, guardedstruct: 2]
    end
  end

  # Note: arity-3 `conditional_field(name, type, opts_with_do)` is what Spark
  # generates directly; we don't override it. Only the arity-4 wrapper below
  # is needed for `conditional_field name, type, opts do … end` calls.

  @doc """
  Arity-4 wrapper for `sub_field name, type, opts do … end`.

  Elixir parses that as arity 4 (positional opts + trailing `do` keyword), but
  Spark generates the entity macro at arity 3 — so we merge here and delegate.
  """
  defmacro sub_field(name, type, opts, do_block) when is_list(opts) and is_list(do_block) do
    merged = opts ++ do_block

    quote do
      sub_field(unquote(name), unquote(type), unquote(merged))
    end
  end

  @doc """
  Arity-4 wrapper for `conditional_field name, type, opts do … end`. Same
  arity-fixup pattern as `sub_field/4`.
  """
  defmacro conditional_field(name, type, opts, do_block)
           when is_list(opts) and is_list(do_block) do
    merged = opts ++ do_block

    quote do
      conditional_field(unquote(name), unquote(type), unquote(merged))
    end
  end

  @doc """
  Arity-2 wrapper around Spark's section macro `guardedstruct/1`.

  Translates top-level options like `guardedstruct enforce: true, module: Foo do …`
  into schema-option setter calls placed at the head of the section body, then
  re-enters the arity-1 form. Spark's section schema validates each option and
  the transformer chain consumes them.

  Also pre-validates literal `field/3` calls in the body to raise legacy-
  compatible `ArgumentError`s for non-atom names and duplicate names. Spark's
  schema validator would emit `Spark.Error.DslError` instead, which existing
  tests don't recognize.
  """
  defmacro guardedstruct(opts, do: block) when is_list(opts) do
    validate_block!(block)

    setters =
      Enum.map(opts, fn {key, value} ->
        # AST for `key(value)` — invokes Spark's auto-generated setter macro.
        {key, [], [value]}
      end)

    full_block = {:__block__, [], setters ++ [block]}

    quote do
      require GuardedStruct.Dsl
      import GuardedStruct, only: [sub_field: 4, conditional_field: 4]

      GuardedStruct.Dsl.guardedstruct do
        unquote(full_block)
      end
    end
  end

  @doc """
  Arity-1 form: `guardedstruct do … end` with no top-level options. Validates
  the body AST and delegates to `GuardedStruct.Dsl.guardedstruct/1`.
  """
  defmacro guardedstruct(do: block) do
    validate_block!(block)

    quote do
      require GuardedStruct.Dsl
      import GuardedStruct, only: [sub_field: 4, conditional_field: 4]

      GuardedStruct.Dsl.guardedstruct do
        unquote(block)
      end
    end
  end

  # Validate only the top-level `field(...)` calls in the section body. We do
  # NOT descend into nested `sub_field` / `conditional_field` blocks here —
  # each nested scope has its own field-name namespace and is validated
  # separately when its block is processed.
  #
  # Catch:
  #   * `field(non_atom_literal, …)` → ArgumentError "a field name must be an
  #      atom, got X"
  #   * Two literal `field(:same_name, …)` calls at the SAME level →
  #      ArgumentError "the field :name is already set"
  #
  # We only flag literals (numbers, strings). Variable references pass through
  # and are checked by our transformer at compile time.
  defp validate_block!(block) do
    items =
      case block do
        {:__block__, _, list} -> list
        single -> [single]
      end

    Enum.reduce(items, [], fn
      {:field, _meta, [name | _]}, seen ->
        cond do
          is_atom(name) and not is_nil(name) ->
            if name in seen do
              raise ArgumentError, "the field #{inspect(name)} is already set"
            end

            [name | seen]

          is_number(name) or is_binary(name) ->
            raise ArgumentError, "a field name must be an atom, got #{inspect(name)}"

          true ->
            seen
        end

      _, seen ->
        # Skip non-field calls (sub_field, conditional_field, opt setters, etc.)
        seen
    end)

    :ok
  end
end
