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

  ## Atom-attack safety

  GuardedStruct accepts both atom-keyed and string-keyed input maps for
  convenience (e.g. JSON payloads come with string keys). The runtime
  must convert string keys to atoms to match your declared field names —
  and that conversion is the classic atom-table-exhaustion DoS vector
  in Elixir.

  ### How GuardedStruct defends — two layers

  **Layer 1.** `Parser.convert_to_atom_map/2` uses `String.to_existing_atom/1`
  rather than `String.to_atom/1`. String keys are converted ONLY if the
  atom already exists (i.e. matches a `field`/`sub_field`/`conditional_field`
  declaration elsewhere in your codebase). Unknown / attacker-controlled
  keys stay as strings — they cannot grow the atom table.

  **Layer 2.** `dynamic_field` values are **identity-preserved** —
  whatever map you submit (string keys, atom keys, mixed, nested) is
  byte-identical to what comes back from `builder/1`. No key conversion
  at any depth.

      defmodule Doc do
        use GuardedStruct
        guardedstruct do
          field         :id,       String.t(), enforce: true
          dynamic_field :metadata
        end
      end

      Doc.builder(%{id: "x", metadata: %{"foo" => 1, :bar => 2, "baz" => %{"nested" => 3}}})
      # => {:ok, %Doc{id: "x", metadata: %{"foo" => 1, :bar => 2, "baz" => %{"nested" => 3}}}}
      #                                    ↑              ↑           ↑
      #                              string stays      atom stays      deep nested string STAYS

  ### How to consume `dynamic_field` values safely

  When the input came from JSON / any untrusted source, your dynamic_field
  ends up with string keys exactly as the sender wrote them:

      def receive(%{"id" => id, "metadata" => meta}) do
        {:ok, doc} = Doc.builder(%{id: id, metadata: meta})
        name = doc.metadata["customer_name"]   # ← read with string keys
        plan = doc.metadata["plan_tier"]
      end

  If you need atom keys for ergonomics (e.g. `doc.metadata.foo`
  dot-access), convert AT THE BOUNDARY where you know which keys are
  safe:

      safe_keys = ~w(customer_name plan_tier signup_source)a   # ← compile-time list

      atomized =
        for k <- safe_keys, into: %{} do
          {k, Map.get(doc.metadata, Atom.to_string(k))}
        end

  That converts only the keys YOU declared in source — the atom table
  cannot grow from user input regardless of what the request body
  contains.

  ### What NOT to do

      # ❌ NEVER do this on user-controlled maps:
      metadata = doc.metadata |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
      #                                              ^^^^^^^^^^^^^^^^^
      #                       creates a new atom from EVERY key the user sent.

  The library protects you on the way IN. Don't undo that protection on
  the way OUT.

  ### Reporting a vulnerability

  See `SECURITY.md` for the security policy and how to report.
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

  # Every entity type that accepts a `:derives` opt. `@derives "..."` /
  # `@derive_rules "..."` decorators get consumed by the very next call to
  # any of these.
  @decoratable_entities [:field, :sub_field, :conditional_field, :virtual_field, :dynamic_field]

  # Walk the block and convert any `@derive_rules "..."` / `@derives "..."`
  # decorator that sits immediately above a decoratable entity call into an
  # inline `derives: "..."` opt on that entity. One-shot — consumed by the
  # very next entity declaration, like `@doc`.
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
       when op in @decoratable_entities and not is_nil(pending) do
    new_args = args |> inject_derive(pending) |> recurse_into_block()
    do_transform_derive_rules(rest, nil, [{op, meta, new_args} | acc])
  end

  defp do_transform_derive_rules([{op, meta, args} | rest], pending, acc)
       when op in @decoratable_entities do
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
      # field/sub_field/conditional_field/virtual_field with explicit opts
      [name, type, opts] when is_list(opts) ->
        [name, type, put_derive(opts, derive_str)]

      # field/sub_field/conditional_field/virtual_field with opts AND do-block
      [name, type, opts, do_block] when is_list(opts) and is_list(do_block) ->
        [name, type, put_derive(opts, derive_str), do_block]

      # field/sub_field/conditional_field/virtual_field with NO opts
      # (note: type is an AST tuple, never a list — `is_tuple(type)` distinguishes
      # this case from `dynamic_field name, [opts]` below).
      [name, type] when is_tuple(type) ->
        [name, type, [derives: derive_str]]

      # dynamic_field with opts — args: [:name] in DSL, opts is a keyword list
      [name, opts] when is_atom(name) and is_list(opts) ->
        [name, put_derive(opts, derive_str)]

      # dynamic_field with NO opts at all
      [name] when is_atom(name) ->
        [name, [derives: derive_str]]

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
