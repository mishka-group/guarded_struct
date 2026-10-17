defmodule GuardedStruct.Derive.Parser do
  @moduledoc false

  @typed_equal_prefixes ["String::", "Integer::", "Float::", "Atom::", "Map::", "Tuple::"]

  @doc """
  Parse a derive string into `%{sanitize: [...], validate: [...]}`.

  Returns `nil` for `nil`, empty and blank input, and for a string `parse/1` reports as an error.
  An operand that is not understood is kept in its list as
  `{:invalid_operand, source}` so `OpParamValidator` can reject it at compile time.
  """
  @spec parser(nil | String.t() | [String.t()]) :: nil | map() | [map()]
  def parser(nil), do: nil
  def parser(""), do: nil

  def parser(inputs) when is_list(inputs), do: Enum.map(inputs, &parser/1)

  def parser(input) when is_binary(input) do
    case parse(input) do
      {:ok, ops} -> ops
      {:error, _reason} -> nil
    end
  end

  @doc """
  Like `parser/1`, but a string that cannot be read is reported as
  `{:error, reason}` instead of `nil`: one the AST parser refuses, a group that
  is not `sanitize(...)` or `validate(...)`, and a group that is not closed.
  An empty or blank string is `{:ok, nil}`.
  """
  @spec parse(nil | String.t()) :: {:ok, nil | map()} | {:error, String.t()}
  def parse(nil), do: {:ok, nil}
  def parse(""), do: {:ok, nil}

  def parse(input) when is_binary(input) do
    case to_block_ast(input) do
      {:ok, ast} -> ast |> normalize_block() |> collect_groups()
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, error} -> {:error, syntax_error_message(error)}
    end
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  defp to_block_ast(input) do
    quoted = input |> String.trim() |> quote_operand_values()

    with :ok <- check_closed(quoted) do
      quoted
      |> String.replace(~r/\)\s+/u, ")\n")
      |> then(&"(\n#{&1}\n)")
      |> Code.string_to_quoted(emit_warnings: false)
    end
  end

  defp syntax_error_message({_meta, {prefix, suffix}, token}),
    do: first_line("#{prefix}#{token}#{suffix}")

  defp syntax_error_message({_meta, message, token}) when is_binary(message),
    do: first_line("#{message}#{token}")

  defp first_line(message), do: message |> String.split("\n", parts: 2) |> hd()

  defp quote_operand_values(input), do: rewrite_operands(input, "")

  defp rewrite_operands("", acc), do: acc

  defp rewrite_operands(<<"regex", rest::binary>>, acc) do
    {ws, after_ws} = take_ws(rest)

    case after_ws do
      <<?=, after_eq::binary>> ->
        case after_eq do
          <<q, _::binary>> when q in [?", ?'] ->
            rewrite_operands(after_eq, acc <> "regex" <> ws <> "=")

          _ ->
            {pattern, remaining} = read_unquoted(after_eq, 0, "")
            cleaned = pattern |> String.trim_trailing() |> escape_for_string_literal()
            rewrite_operands(remaining, acc <> "regex" <> ws <> ~s(=") <> cleaned <> ~s("))
        end

      _ ->
        rewrite_operands(rest, acc <> "regex")
    end
  end

  # `equal=Type::value` reads as `(equal=Type)::value` to the Elixir parser, so
  # the operand is wrapped in a string literal the same way a regex is.
  defp rewrite_operands(<<"equal", rest::binary>>, acc) do
    {ws, after_ws} = take_ws(rest)

    with <<?=, after_eq::binary>> <- after_ws,
         {ws_eq, operand} = take_ws(after_eq),
         true <- op_boundary?(acc) and typed_equal_operand?(operand) do
      {value, remaining} = read_unquoted(operand, 0, "")
      cleaned = value |> String.trim_trailing() |> escape_for_string_literal()
      quoted = "equal" <> ws <> "=" <> ws_eq <> ~s(") <> cleaned <> ~s(")
      rewrite_operands(remaining, acc <> quoted)
    else
      _ -> rewrite_operands(rest, acc <> "equal")
    end
  end

  defp rewrite_operands(<<c, rest::binary>>, acc), do: rewrite_operands(rest, <<acc::binary, c>>)

  defp typed_equal_operand?(operand),
    do: Enum.any?(@typed_equal_prefixes, &String.starts_with?(operand, &1))

  defp op_boundary?(""), do: true
  defp op_boundary?(acc), do: not identifier_char?(:binary.last(acc))

  defp identifier_char?(char),
    do: char in ?a..?z or char in ?A..?Z or char in ?0..?9 or char == ?_

  defp take_ws(input), do: take_ws(input, "")

  defp take_ws(<<c, rest::binary>>, acc) when c in [?\s, ?\t],
    do: take_ws(rest, <<acc::binary, c>>)

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

  # A group that is not closed is an error: the `(` that opens it is named.
  defp check_closed(source) do
    {open, _state, _index} =
      source
      |> :binary.bin_to_list()
      |> Enum.reduce({[], :code, 0}, fn ch, {open, state, index} ->
        {open, state} = scan_char(ch, index, open, state)
        {open, state, index + 1}
      end)

    case List.last(open) do
      nil -> :ok
      index -> {:error, "the group `#{group_source(source, index)}` is not closed, add `)`"}
    end
  end

  defp scan_char(ch, index, open, state) do
    case {state, ch} do
      {:in_string, ?\\} -> {open, :string_escape}
      {:string_escape, _} -> {open, :in_string}
      {:in_string, ?"} -> {open, :code}
      {:in_string, _} -> {open, :in_string}
      {:in_charlist, ?\\} -> {open, :charlist_escape}
      {:charlist_escape, _} -> {open, :in_charlist}
      {:in_charlist, ?'} -> {open, :code}
      {:in_charlist, _} -> {open, :in_charlist}
      {:code, ?"} -> {open, :in_string}
      {:code, ?'} -> {open, :in_charlist}
      {:code, ?(} -> {[index | open], :code}
      {:code, ?)} -> {Enum.drop(open, 1), :code}
      {:code, _} -> {open, :code}
    end
  end

  defp group_source(source, index) do
    before = :binary.part(source, 0, index)
    name = before |> then(&Regex.run(~r/[A-Za-z_][A-Za-z0-9_]*$/, &1)) |> List.wrap() |> hd_or("")
    rest = :binary.part(source, index, byte_size(source) - index)
    shorten(name <> rest)
  end

  defp hd_or([], default), do: default
  defp hd_or([head | _], _default), do: head

  defp shorten(text) do
    text = String.trim(text)
    if String.length(text) > 40, do: String.slice(text, 0, 40) <> "...", else: text
  end

  defp normalize_block({:__block__, _, calls}), do: calls
  defp normalize_block(single_call), do: [single_call]

  defp nilify_empty(map) when map == %{}, do: nil
  defp nilify_empty(map), do: map

  defp collect_groups(calls) do
    case Enum.find(calls, &(not group?(&1))) do
      nil -> {:ok, calls |> Enum.reduce(%{}, &collect_call/2) |> nilify_empty()}
      other -> {:error, unknown_group_message(other)}
    end
  end

  defp group?({op, _meta, args}) when op in [:sanitize, :validate] and is_list(args), do: true
  defp group?(_other), do: false

  defp unknown_group_message(ast) do
    "unknown group `#{ast |> Macro.to_string() |> shorten()}`, write `sanitize(...)` or `validate(...)`"
  end

  defp collect_call({op, _meta, args}, acc) do
    parsed = Enum.map(args, &(&1 |> fold_negative_numbers() |> parse_arg()))
    Map.update(acc, op, parsed, &(&1 ++ parsed))
  end

  # `-10` reaches the AST as a unary minus call on `10`, not as a literal.
  defp fold_negative_numbers(ast) do
    Macro.prewalk(ast, fn
      {:-, _meta, [number]} when is_number(number) -> -number
      other -> other
    end)
  end

  defp parse_arg({atom, _meta, nil}) when is_atom(atom), do: atom

  defp parse_arg({:=, _, [{:custom, _, nil}, value]} = ast) when is_list(value) do
    case value do
      [{:__aliases__, _, mods}, {fun, _, nil}] when is_atom(fun) ->
        {:custom, {mods, fun}}

      _ ->
        invalid_operand(ast)
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
       when is_atom(key) and is_number(value),
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
      %{key => Enum.map(value, &parse_arg/1)}
    else
      {key, value}
    end
  end

  defp parse_arg({:=, _, [{key, _, nil}, {_, _, [{:__aliases__, _, [type]} | _]} = value]})
       when is_atom(key) and is_atom(type) do
    {key, ast_to_string(value)}
  end

  defp parse_arg({:=, _, [{key, _, nil}, value]} = ast) when is_atom(key) do
    if Macro.quoted_literal?(value) do
      {literal, _binding} = Code.eval_quoted(value)
      {key, literal}
    else
      invalid_operand(ast)
    end
  end

  defp parse_arg(other), do: invalid_operand(other)

  defp invalid_operand(ast), do: {:invalid_operand, ast_to_string(ast)}

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

  `nested` is a function that receives the converted key of a nested value
  and returns that value's conversion spec — `%{passthrough: [atom()], nested:
  function}` — or `nil` for the plain deep conversion. The runtime uses it so a
  `dynamic_field` inside a `sub_field` keeps its keys too.

  Structs are never converted: a `%Time{}` or `%URI{}` nested in the input
  reaches the validators as the struct it was.

  See the "Atom-attack safety" section of the `GuardedStruct` module
  `@moduledoc` for the threat model and the recommended pattern when
  consuming user-supplied data into a `dynamic_field`.
  """
  @spec convert_to_atom_map(
          {:ok, map()} | {:error, any(), any()} | map(),
          [atom()],
          map() | nil,
          (atom() -> map() | nil) | nil
        ) :: {:error, any(), any()} | map()
  def convert_to_atom_map(
        map_or_result,
        passthrough_keys \\ [],
        atom_lookup \\ nil,
        nested \\ nil
      )

  def convert_to_atom_map({:error, _, _} = error, _, _, _), do: error

  def convert_to_atom_map({:ok, map}, pt, lookup, nested) when is_map(map),
    do: convert_to_atom_map(map, pt, lookup, nested)

  def convert_to_atom_map(map, pt, lookup, nested) when is_struct(map) do
    do_convert(Map.from_struct(map), pt, lookup, nested)
  end

  def convert_to_atom_map(map, pt, lookup, nested) when is_map(map) do
    do_convert(map, pt, lookup, nested)
  end

  defp do_convert(map, passthrough_keys, atom_lookup, nested) do
    passthrough = MapSet.new(passthrough_keys)

    for {k, v} <- map, into: %{} do
      atom_key = convert_key(k, atom_lookup)

      new_value =
        if MapSet.member?(passthrough, atom_key),
          do: v,
          else: convert_value(v, nested_spec(nested, atom_key))

      {atom_key, new_value}
    end
  end

  defp nested_spec(nil, _key), do: nil
  defp nested_spec(nested, key), do: nested.(key)

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

  defp convert_value(%{__struct__: _} = struct, _spec), do: struct
  defp convert_value(%{} = map, nil), do: convert_to_atom_map(map)

  defp convert_value(%{} = map, %{passthrough: passthrough, nested: nested}),
    do: do_convert(map, passthrough, nil, nested)

  defp convert_value([], _spec), do: []
  defp convert_value(list, spec) when is_list(list), do: Enum.map(list, &convert_value(&1, spec))
  defp convert_value(value, _spec), do: value

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
