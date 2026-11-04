defmodule GuardedStruct.Derive.SanitizerDerive do
  @moduledoc """
  Built-in sanitizer ops. Every clause follows the pipe-friendly
  `sanitize(value, op)` argument order:

      "  Hello  " |> SanitizerDerive.sanitize(:trim) |> SanitizerDerive.sanitize(:downcase)
      # => "hello"

  An op is served by the first that knows it: the built-in ops, then the derive
  extensions of the module being built, then its `sanitize_derive` modules in order.
  A `sanitize_derive` module passes an op on to the next one by returning `nil`, or
  by having no `sanitize/2` clause that matches the value and the op.

  Sanitizing fails closed:

    * a sanitizer that raises never lets the raw value through. In a `derives`
      string the field fails with a `:sanitize` error and the exception is logged
      (see `call/2`); `sanitize/2` raises the exception.
    * an op that nothing serves raises `ArgumentError`, because the op is a
      programming mistake.
  """

  require Logger

  import GuardedStruct.Messages, only: [translated_message: 2]

  alias GuardedStruct.Derive
  alias GuardedStruct.Derive.{Extension, Registry}

  @control_chars ~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/
  @zero_width_chars ~r/[\x{200B}-\x{200D}\x{FEFF}\x{2060}]/u

  @string_ops [:basic_html, :html5, :markdown_html, :strip_tags, :string_float, :string_integer]

  @typep result :: {:ok, any()} | {:crashed, any(), Exception.t(), Exception.stacktrace()}

  @doc """
  Runs the sanitize ops of a field in order and returns `{field, value}`.

  When a sanitizer raises, `value` is the field's `:sanitize` error
  (`{:error, field, :sanitize, message}`), which
  `GuardedStruct.Derive.ValidationDerive.call/3` reports like any other field
  error. The exception is logged at error level with its stacktrace, without the
  arguments of each call, so the value itself is never logged.
  """
  @spec call({atom(), any()}, list(any()) | nil) :: {atom(), any()}
  def call({field, input}, nil), do: {field, input}

  def call({field, input}, actions) do
    case run_all(input, actions) do
      {:ok, value} -> {field, value}
      {:crashed, op, exception, stacktrace} -> {field, failed(field, op, exception, stacktrace)}
    end
  end

  @doc """
  Applies one sanitize op to `input`. Raises what the sanitizer raises, and
  `ArgumentError` for an op that nothing serves.
  """
  @spec sanitize(any(), atom() | tuple() | map()) :: any()
  def sanitize(input, op) do
    case run(input, op) do
      {:ok, value} -> value
      {:crashed, _op, exception, stacktrace} -> reraise exception, stacktrace
    end
  end

  @spec run_all(any(), list(any())) :: result()
  defp run_all(input, ops) do
    Enum.reduce_while(ops, {:ok, input}, fn op, {:ok, acc} ->
      case run(acc, op) do
        {:ok, _value} = ok -> {:cont, ok}
        crashed -> {:halt, crashed}
      end
    end)
  end

  @spec run(any(), any()) :: result()
  defp run(input, {:each, inner}) when is_list(input) and is_list(inner),
    do: run_each(input, inner)

  defp run(input, %{each: inner}) when is_list(input) and is_list(inner),
    do: run_each(input, inner)

  defp run(input, {:tag, type}) when is_binary(input),
    do: run_all(input, [:trim, tag_op(type), :trim])

  defp run(input, op) do
    if Registry.known_sanitize?(op_name(op)),
      do: attempt(op, fn -> builtin(input, op) end),
      else: delegate(input, op)
  end

  defp run_each(items, inner) do
    result =
      Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
        case run_all(item, inner) do
          {:ok, value} -> {:cont, {:ok, [value | acc]}}
          crashed -> {:halt, crashed}
        end
      end)

    with {:ok, reversed} <- result, do: {:ok, Enum.reverse(reversed)}
  end

  defp delegate(input, op) do
    case attempt(op, fn -> Extension.dispatch_sanitize(input, op) end) do
      {:ok, :__not_found__} -> run_modules(Derive.fallback_modules(:sanitize_derive), input, op)
      result -> result
    end
  end

  defp run_modules([], _input, op) do
    raise ArgumentError,
          "no sanitizer serves the sanitize op #{inspect(op)}: it is not a built-in op, " <>
            "no derive extension of the module declares it, and no `sanitize_derive` " <>
            "module returns a value for it. Declare it with `GuardedStruct.Derive.Extension`, " <>
            "give a `sanitize_derive` module a `sanitize/2` clause for it, or fix the typo."
  end

  defp run_modules([module | rest], input, op) do
    case attempt(op, fn -> module.sanitize(input, op) end) do
      {:ok, nil} ->
        run_modules(rest, input, op)

      {:crashed, _op, %FunctionClauseError{module: ^module, function: :sanitize, arity: 2}, _} ->
        run_modules(rest, input, op)

      result ->
        result
    end
  end

  # The only place a sanitizer's exception is caught. It becomes a result, so the
  # caller decides: `call/2` fails the field, `sanitize/2` raises it again.
  defp attempt(op, fun) do
    {:ok, fun.()}
  rescue
    exception -> {:crashed, op, exception, __STACKTRACE__}
  end

  defp failed(field, op, exception, stacktrace) do
    stacktrace = Enum.map(stacktrace, &without_args/1)

    Logger.error(
      "GuardedStruct could not sanitize the #{field} field with #{inspect(op)}\n" <>
        Exception.format(:error, exception, stacktrace),
      crash_reason: {exception, stacktrace}
    )

    {:error, field, :sanitize, translated_message(:sanitize, field)}
  end

  defp without_args({module, function, args, location}) when is_list(args),
    do: {module, function, length(args), location}

  defp without_args(entry), do: entry

  defp op_name(op) when is_atom(op), do: op
  defp op_name({op, _arg}) when is_atom(op), do: op
  defp op_name(%{each: _inner}), do: :each
  defp op_name(_op), do: nil

  defp tag_op(type) when is_binary(type), do: String.to_atom(type)
  defp tag_op(type), do: type

  defp builtin(input, :trim) do
    if is_binary(input), do: String.trim(input), else: input
  end

  defp builtin(input, :upcase) do
    if is_binary(input), do: String.upcase(input), else: input
  end

  defp builtin(input, :downcase) do
    if is_binary(input), do: String.downcase(input), else: input
  end

  defp builtin(input, :capitalize) do
    if is_binary(input), do: String.capitalize(input), else: input
  end

  if Code.ensure_loaded?(HtmlSanitizeEx) do
    defp builtin(input, :basic_html) when is_binary(input), do: HtmlSanitizeEx.basic_html(input)

    defp builtin(input, :html5) when is_binary(input), do: HtmlSanitizeEx.html5(input)

    defp builtin(input, :markdown_html) when is_binary(input),
      do: HtmlSanitizeEx.markdown_html(input)

    defp builtin(input, :strip_tags) when is_binary(input), do: HtmlSanitizeEx.strip_tags(input)

    defp builtin(input, :string_float) when is_binary(input) do
      case input |> builtin(:strip_tags) |> Float.parse() do
        :error -> 0.0
        {converted_float, _} -> converted_float
      end
    end

    defp builtin(input, :string_integer) when is_binary(input) do
      case input |> builtin(:strip_tags) |> Integer.parse() do
        :error -> 0
        {converted_integer, _} -> converted_integer
      end
    end
  else
    defp builtin(input, :string_float) when is_binary(input) do
      case Float.parse(input) do
        :error -> 0.0
        {converted_float, _} -> converted_float
      end
    end

    defp builtin(input, :string_integer) when is_binary(input) do
      case Integer.parse(input) do
        :error -> 0
        {converted_integer, _} -> converted_integer
      end
    end
  end

  defp builtin(input, op) when op in @string_ops and not is_binary(input), do: input

  defp builtin(input, {:tag, _type}), do: input

  defp builtin(input, :uniq) when is_list(input), do: Enum.uniq(input)
  defp builtin(input, :uniq), do: input

  defp builtin(input, :compact) when is_list(input), do: Enum.reject(input, &is_nil/1)
  defp builtin(input, :compact), do: input

  defp builtin(input, :reject_empty) when is_list(input) do
    Enum.reject(input, fn
      nil -> true
      "" -> true
      [] -> true
      %{} = m when map_size(m) == 0 -> true
      _ -> false
    end)
  end

  defp builtin(input, :reject_empty), do: input

  defp builtin(input, :sort) when is_list(input), do: Enum.sort(input)
  defp builtin(input, :sort), do: input

  defp builtin(input, :squish) when is_binary(input),
    do: input |> String.split() |> Enum.join(" ")

  defp builtin(input, :squish), do: input

  defp builtin(input, :no_control) when is_binary(input),
    do: String.replace(input, @control_chars, "")

  defp builtin(input, :no_control), do: input

  defp builtin(input, :no_zero_width) when is_binary(input),
    do: String.replace(input, @zero_width_chars, "")

  defp builtin(input, :no_zero_width), do: input

  defp builtin(input, :rich_text_safe) when is_binary(input) do
    input
    |> builtin(:no_zero_width)
    |> builtin(:no_control)
  end

  defp builtin(input, :rich_text_safe), do: input

  defp builtin(input, {:clamp, [min, max]})
       when is_number(input) and is_number(min) and is_number(max) do
    cond do
      input < min -> min
      input > max -> max
      true -> input
    end
  end

  defp builtin(input, {:clamp, _}), do: input

  defp builtin(nil, {:default_when_nil, value}), do: value
  defp builtin(input, {:default_when_nil, _}), do: input

  defp builtin(nil, {:default_when_empty, value}), do: value
  defp builtin("", {:default_when_empty, value}), do: value
  defp builtin([], {:default_when_empty, value}), do: value
  defp builtin(%{} = m, {:default_when_empty, value}) when map_size(m) == 0, do: value
  defp builtin(input, {:default_when_empty, _}), do: input

  defp builtin(input, {:each, _inner}), do: input
  defp builtin(input, %{each: _inner}), do: input
end
