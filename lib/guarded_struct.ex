defmodule GuardedStruct do
  @moduledoc """
  GuardedStruct macro: build structs with validation, sanitization, constructors,
  and nested-struct support.

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
  """

  use Spark.Dsl, default_extensions: [extensions: [GuardedStruct.Dsl]]

  defmacro __using__(opts) do
    super_opts = Keyword.drop(opts, [:derive_extensions])
    super_ast = super(super_opts)

    derive_extensions_opt =
      opts
      |> Keyword.get(:derive_extensions)
      |> resolve_extension_aliases(__CALLER__)

    # Validate at compile time so typos / bad shapes fail loudly here, not
    # silently at the first builder/1 call.
    GuardedStruct.Derive.Extension.validate_opt!(derive_extensions_opt)

    derive_extensions_ast = Macro.escape(derive_extensions_opt)

    quote do
      unquote(super_ast)
      import GuardedStruct.Dsl, only: []
      import GuardedStruct, only: [guardedstruct: 1, guardedstruct: 2]

      @__guarded_derive_extensions_opt__ unquote(derive_extensions_ast)

      @doc false
      def __guarded_derive_extensions_opt__, do: @__guarded_derive_extensions_opt__
    end
  end

  # When the `derive_extensions:` opt is passed in source as
  # `[Foo.Bar, :config]`, Elixir hands the macro the AST form
  # `[{:__aliases__, _, [:Foo, :Bar]}, :config]`. We resolve aliases via
  # `Macro.expand/2` against the caller's environment — that's the only
  # way to honour `alias Foo` AND nested-module context (so `LocalDerives`
  # inside test/X.exs becomes the fully-qualified `Test.X.LocalDerives`).
  defp resolve_extension_aliases(nil, _caller), do: nil

  defp resolve_extension_aliases(list, caller) when is_list(list) do
    Enum.map(list, fn
      {:__aliases__, _, _} = ast -> Macro.expand(ast, caller)
      other -> other
    end)
  end

  defp resolve_extension_aliases(other, _caller), do: other

  @doc "Arity-4 wrapper for `sub_field name, type, opts do … end`."
  defmacro sub_field(name, type, opts, do_block) when is_list(opts) and is_list(do_block) do
    merged = opts ++ do_block

    quote do
      sub_field(unquote(name), unquote(type), unquote(merged))
    end
  end

  @doc "Arity-4 wrapper for `conditional_field name, type, opts do … end`."
  defmacro conditional_field(name, type, opts, do_block)
           when is_list(opts) and is_list(do_block) do
    merged = opts ++ do_block

    quote do
      conditional_field(unquote(name), unquote(type), unquote(merged))
    end
  end

  @doc """
  `guardedstruct opts do … end` — top-level options like `enforce: true` or
  `module: Foo` are lifted into setter calls inside the section body.
  """
  defmacro guardedstruct(opts, do: block) when is_list(opts) do
    block = transform_derive_rules(block)
    validate_block!(block)
    block_enforce? = Keyword.get(opts, :enforce, false) == true
    pre_enforce_keys = extract_enforce_keys(block, block_enforce?)
    block_aliases = extract_aliases(block)

    setters =
      Enum.map(opts, fn {key, value} ->
        {key, [], [value]}
      end)

    full_block = {:__block__, [], setters ++ [block]}

    quote do
      require GuardedStruct.Dsl
      import GuardedStruct, only: [sub_field: 4, conditional_field: 4]

      unquote_splicing(block_aliases)

      GuardedStruct.Dsl.guardedstruct do
        unquote(full_block)
      end

      @enforce_keys unquote(pre_enforce_keys)
    end
  end

  @doc "`guardedstruct do … end` — no top-level options."
  defmacro guardedstruct(do: block) do
    block = transform_derive_rules(block)
    validate_block!(block)
    pre_enforce_keys = extract_enforce_keys(block, false)
    block_aliases = extract_aliases(block)

    quote do
      require GuardedStruct.Dsl
      import GuardedStruct, only: [sub_field: 4, conditional_field: 4]

      unquote_splicing(block_aliases)

      GuardedStruct.Dsl.guardedstruct do
        unquote(block)
      end

      @enforce_keys unquote(pre_enforce_keys)
    end
  end

  # Walk the block and convert any `@derive_rules "..."` decorator that sits
  # immediately above a field/sub_field/conditional_field call into an inline
  # `derives: "..."` opt on that field. One-shot — consumed by the very next
  # field-like declaration, like `@doc`.
  defp transform_derive_rules(block) do
    items =
      case block do
        {:__block__, meta, list} -> {:__block__, meta, do_transform_derive_rules(list, nil, [])}
        single -> List.first(do_transform_derive_rules([single], nil, [])) || single
      end

    items
  end

  defp do_transform_derive_rules([], _pending, acc), do: Enum.reverse(acc)

  defp do_transform_derive_rules([{:@, _meta, [{name, _, [rules]}]} | rest], _pending, acc)
       when name in [:derive_rules, :derives] and is_binary(rules) do
    do_transform_derive_rules(rest, rules, acc)
  end

  defp do_transform_derive_rules([{op, meta, args} | rest], pending, acc)
       when op in [:field, :sub_field, :conditional_field] and not is_nil(pending) do
    new_args = args |> inject_derive(pending) |> recurse_into_block()
    do_transform_derive_rules(rest, nil, [{op, meta, new_args} | acc])
  end

  defp do_transform_derive_rules([{op, meta, args} | rest], pending, acc)
       when op in [:field, :sub_field, :conditional_field] do
    new_args = recurse_into_block(args)
    do_transform_derive_rules(rest, pending, [{op, meta, new_args} | acc])
  end

  defp do_transform_derive_rules([item | rest], pending, acc) do
    do_transform_derive_rules(rest, pending, [item | acc])
  end

  # Recurse into a sub_field / conditional_field's `do:` block so `@derives`
  # decorators inside the body are also expanded.
  defp recurse_into_block(args) do
    case args do
      [name, type, opts, [do: do_block]] when is_list(opts) ->
        [name, type, opts, [do: transform_derive_rules(do_block)]]

      [name, type, [{:do, _} | _] = kw] ->
        rewritten = Keyword.update!(kw, :do, fn block -> transform_derive_rules(block) end)
        [name, type, rewritten]

      [name, type, opts] when is_list(opts) ->
        case Keyword.fetch(opts, :do) do
          {:ok, do_block} ->
            [name, type, Keyword.put(opts, :do, transform_derive_rules(do_block))]

          :error ->
            args
        end

      other ->
        other
    end
  end

  defp inject_derive(args, derive_str) do
    case args do
      [name, type, opts] when is_list(opts) ->
        [name, type, put_derive(opts, derive_str)]

      [name, type] ->
        [name, type, [derives: derive_str]]

      [name, type, opts, do_block] when is_list(opts) and is_list(do_block) ->
        [name, type, put_derive(opts, derive_str), do_block]

      other ->
        other
    end
  end

  # Inline `derives:` or `derive:` wins over the decorator. If neither is
  # set, inject under the canonical `derives:` name.
  defp put_derive(opts, derive_str) do
    cond do
      Keyword.has_key?(opts, :derives) -> opts
      Keyword.has_key?(opts, :derive) -> opts
      true -> Keyword.put(opts, :derives, derive_str)
    end
  end

  defp extract_aliases(block) do
    items =
      case block do
        {:__block__, _, list} -> list
        single -> [single]
      end

    Enum.filter(items, fn
      {:alias, _meta, _args} -> true
      _ -> false
    end)
  end

  defp extract_enforce_keys(block, block_enforce?) do
    items =
      case block do
        {:__block__, _, list} -> list
        single -> [single]
      end

    Enum.flat_map(items, fn
      {:field, _meta, [name | rest]} when is_atom(name) and not is_nil(name) ->
        opts =
          case rest do
            [_type, opts] when is_list(opts) -> opts
            [_type] -> []
            _ -> []
          end

        cond do
          Keyword.get(opts, :enforce) == false -> []
          Keyword.get(opts, :enforce) == true -> [name]
          block_enforce? and not Keyword.has_key?(opts, :default) -> [name]
          true -> []
        end

      _other ->
        []
    end)
    |> Enum.reverse()
  end

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
        seen
    end)

    :ok
  end
end
