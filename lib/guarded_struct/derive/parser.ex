defmodule GuardedStruct.Derive.Parser do
  @moduledoc false

  @doc """
  Parse a derive string into `%{sanitize: [...], validate: [...]}`.

  Returns `nil` for `nil`/empty input or for strings the AST parser refuses.
  """
  @spec parser(nil | String.t() | [String.t()]) :: nil | map() | [map()]
  def parser(nil), do: nil
  def parser(""), do: nil

  def parser(inputs) when is_list(inputs), do: Enum.map(inputs, &parser/1)

  def parser(input) when is_binary(input) do
    with {:ok, ast} <- to_block_ast(input) do
      ast
      |> normalize_block()
      |> Enum.reduce(%{}, &collect_call/2)
      |> nilify_empty()
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp to_block_ast(input) do
    wrapped =
      input
      |> String.trim()
      |> quote_regex_values()
      |> balance_parens()
      |> String.replace(~r/\)\s+/u, ")\n")
      |> then(&"(\n#{&1}\n)")

    Code.string_to_quoted(wrapped, emit_warnings: false)
  end

  defp quote_regex_values(input), do: rewrite_regex(input, "")

  defp rewrite_regex("", acc), do: acc

  defp rewrite_regex(<<"regex", rest::binary>>, acc) do
    {ws, after_ws} = take_ws(rest)

    case after_ws do
      <<?=, after_eq::binary>> ->
        case after_eq do
          <<q, _::binary>> when q in [?", ?'] ->
            rewrite_regex(after_eq, acc <> "regex" <> ws <> "=")

          _ ->
            {pattern, remaining} = read_unquoted(after_eq, 0, "")
            cleaned = pattern |> String.trim_trailing() |> escape_for_string_literal()
            rewrite_regex(remaining, acc <> "regex" <> ws <> ~s(=") <> cleaned <> ~s("))
        end

      _ ->
        rewrite_regex(rest, acc <> "regex")
    end
  end

  defp rewrite_regex(<<c, rest::binary>>, acc), do: rewrite_regex(rest, <<acc::binary, c>>)

  defp take_ws(input), do: take_ws(input, "")
  defp take_ws(<<c, rest::binary>>, acc) when c in [?\s, ?\t], do: take_ws(rest, <<acc::binary, c>>)
  defp take_ws(input, acc), do: {acc, input}

  defp read_unquoted(input, 0, ""), do: read_balanced(input, 0, 0, 0, "")

  defp read_balanced("", _b, _p, _q, acc), do: {acc, ""}

  defp read_balanced(<<?\\, c, rest::binary>>, b, p, q, acc),
    do: read_balanced(rest, b, p, q, <<acc::binary, ?\\, c>>)

  defp read_balanced(<<?[, rest::binary>>, b, p, q, acc),
    do: read_balanced(rest, b + 1, p, q, <<acc::binary, ?[>>)

  defp read_balanced(<<?], rest::binary>>, b, p, q, acc) when b > 0,
    do: read_balanced(rest, b - 1, p, q, <<acc::binary, ?]>>)

  defp read_balanced(<<?(, rest::binary>>, b, p, q, acc),
    do: read_balanced(rest, b, p + 1, q, <<acc::binary, ?(>>)

  defp read_balanced(<<?), rest::binary>>, b, p, q, acc) when p > 0,
    do: read_balanced(rest, b, p - 1, q, <<acc::binary, ?)>>)

  defp read_balanced(<<?{, rest::binary>>, b, p, q, acc),
    do: read_balanced(rest, b, p, q + 1, <<acc::binary, ?{>>)

  defp read_balanced(<<?}, rest::binary>>, b, p, q, acc) when q > 0,
    do: read_balanced(rest, b, p, q - 1, <<acc::binary, ?}>>)

  defp read_balanced(<<c, _::binary>> = input, 0, 0, 0, acc) when c in [?], ?,, ?)],
    do: {acc, input}

  defp read_balanced(<<c, rest::binary>>, b, p, q, acc),
    do: read_balanced(rest, b, p, q, <<acc::binary, c>>)

  defp escape_for_string_literal(pattern) do
    pattern
    |> String.replace("\\", "\\\\")
    |> String.replace(~S("), ~S(\"))
  end

  defp balance_parens(input) do
    {depth, _state} =
      input
      |> :binary.bin_to_list()
      |> Enum.reduce({0, :code}, fn ch, {d, state} ->
        case {state, ch} do
          {:in_string, ?\\} -> {d, :string_escape}
          {:string_escape, _} -> {d, :in_string}
          {:in_string, ?"} -> {d, :code}
          {:in_string, _} -> {d, :in_string}
          {:in_charlist, ?\\} -> {d, :charlist_escape}
          {:charlist_escape, _} -> {d, :in_charlist}
          {:in_charlist, ?'} -> {d, :code}
          {:in_charlist, _} -> {d, :in_charlist}
          {:code, ?"} -> {d, :in_string}
          {:code, ?'} -> {d, :in_charlist}
          {:code, ?(} -> {d + 1, :code}
          {:code, ?)} -> {d - 1, :code}
          {:code, _} -> {d, :code}
        end
      end)

    if depth > 0, do: input <> String.duplicate(")", depth), else: input
  end

  defp normalize_block({:__block__, _, calls}), do: calls
  defp normalize_block(single_call), do: [single_call]

  defp nilify_empty(map) when map == %{}, do: nil
  defp nilify_empty(map), do: map

  defp collect_call({op, _meta, args}, acc)
       when op in [:sanitize, :validate] and is_list(args) do
    parsed = args |> Enum.map(&parse_arg/1) |> Enum.reject(&is_nil/1)
    Map.update(acc, op, parsed, &(&1 ++ parsed))
  end

  defp collect_call(_other, acc), do: acc

  defp parse_arg({atom, _meta, nil}) when is_atom(atom), do: atom

  defp parse_arg({:=, _, [{:custom, _, nil}, value]}) when is_list(value) do
    case value do
      [{:__aliases__, _, mods}, {fun, _, nil}] when is_atom(fun) ->
        {:custom, {mods, fun}}

      _ ->
        nil
    end
  end

  defp parse_arg({:=, _, [{key, _, nil}, {value, _, nil}]})
       when key in [:optional, :each] and is_atom(value),
       do: {key, [value]}

  defp parse_arg({:=, _, [{key, _, nil}, {value, _, nil}]})
       when is_atom(key) and is_atom(value) do
    {key, Atom.to_string(value)}
  end

  defp parse_arg({:=, _, [{key, _, nil}, value]})
       when is_atom(key) and is_integer(value),
       do: {key, value}

  defp parse_arg({:=, _, [{key, _, nil}, nil]}) when is_atom(key),
    do: {key, nil}

  defp parse_arg({:=, _, [{:regex, _, nil}, value]}) when is_binary(value),
    do: precompile_regex(value)

  defp parse_arg({:=, _, [{:regex, _, nil}, value]}) when is_list(value),
    do: precompile_regex(to_string(value))

  defp parse_arg({:=, _, [{key, _, nil}, value]})
       when is_atom(key) and is_binary(value),
       do: {key, value}

  defp parse_arg({:=, _, [{key, _, nil}, value]})
       when is_atom(key) and is_list(value) do
    if Enum.any?(value, &is_tuple/1) do
      inner = value |> Enum.map(&parse_arg/1) |> Enum.reject(&is_nil/1)
      if inner == [], do: nil, else: %{key => inner}
    else
      {key, value}
    end
  end

  defp parse_arg({:=, _, [{key, _, nil}, {_, _, [{:__aliases__, _, [type]} | _]} = value]})
       when is_atom(key) and is_atom(type) do
    {key, ast_to_string(value)}
  end

  defp parse_arg(_other), do: nil

  defp precompile_regex(source) do
    case Regex.compile(source) do
      {:ok, regex} -> {:regex, regex}
      {:error, _} -> {:regex, source}
    end
  end

  defp ast_to_string(ast) do
    ast |> Macro.update_meta(fn _ -> [] end) |> Macro.to_string()
  end

  @doc """
  Recursively convert string keys to atoms in a map.

  ## Atom-attack safety

  This function is **doubly defensive** against atom-table-exhaustion DoS:

    1. It uses `String.to_existing_atom/1` — string keys are converted to
       atoms ONLY if the atom already exists in the atom table. Unknown
       keys (e.g. attacker-controlled inputs) stay as strings.

    2. `convert_to_atom_map/2` accepts an optional `passthrough_keys` list.
       Values whose key is in that list are LEFT ENTIRELY UNTOUCHED — no
       recursion, no key conversion at any depth. The runtime uses this
       to mark `dynamic_field` values, so their free-form inner shapes
       round-trip exactly as the user submitted them.

  See the "Atom-attack safety" section of the `GuardedStruct` module
  `@moduledoc` for the threat model and the recommended pattern when
  consuming user-supplied data into a `dynamic_field`.
  """
  @spec convert_to_atom_map(
          {:ok, map()} | {:error, any(), any()} | map(),
          [atom()],
          map() | nil
        ) :: {:error, any(), any()} | map()
  def convert_to_atom_map(map_or_result, passthrough_keys \\ [], atom_lookup \\ nil)

  def convert_to_atom_map({:error, _, _} = error, _, _), do: error

  def convert_to_atom_map({:ok, map}, pt, lookup) when is_map(map),
    do: convert_to_atom_map(map, pt, lookup)

  def convert_to_atom_map(map, pt, lookup) when is_struct(map) do
    do_convert(Map.from_struct(map), pt, lookup)
  end

  def convert_to_atom_map(map, pt, lookup) when is_map(map) do
    do_convert(map, pt, lookup)
  end

  defp do_convert(map, passthrough_keys, atom_lookup) do
    passthrough = MapSet.new(passthrough_keys)

    for {k, v} <- map, into: %{} do
      atom_key = convert_key(k, atom_lookup)
      new_value = if MapSet.member?(passthrough, atom_key), do: v, else: convert_value(v)
      {atom_key, new_value}
    end
  end

  defp convert_key(key, lookup) when is_binary(key) and is_map(lookup) do
    case Map.fetch(lookup, key) do
      {:ok, atom} -> atom
      :error -> safe_to_existing_atom(key)
    end
  end

  defp convert_key(key, _lookup) when is_binary(key), do: safe_to_existing_atom(key)
  defp convert_key(key, _lookup), do: key

  defp safe_to_existing_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  defp convert_value(%{__struct__: s} = m) when s in [NaiveDateTime, DateTime, Date], do: m
  defp convert_value(%{} = m), do: convert_to_atom_map(m)
  defp convert_value([]), do: []
  defp convert_value(list) when is_list(list), do: Enum.map(list, &convert_value/1)
  defp convert_value(value), do: value

  @spec parse_core_keys_pattern(binary()) :: [atom()]
  def parse_core_keys_pattern(pattern) do
    pattern
    |> String.trim()
    |> String.split("::", trim: true)
    |> Enum.map(&String.to_atom/1)
  end

  @spec convert_parameters(atom() | String.t(), any()) :: nil | %{optional(any()) => list()}
  def convert_parameters(derive_key, parameters) when is_list(parameters) do
    converted = parameters |> Enum.map(&parse_arg/1) |> Enum.reject(&is_nil/1)
    if converted == [], do: nil, else: %{derive_key => converted}
  end

  def convert_parameters(_derive_key, _parameters), do: nil
end
