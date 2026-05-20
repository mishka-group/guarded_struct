defmodule GuardedStruct.Derive.SanitizerDerive do
  @moduledoc """
  Built-in sanitizer ops. Every clause follows the pipe-friendly
  `sanitize(value, op)` argument order:

      "  Hello  " |> SanitizerDerive.sanitize(:trim) |> SanitizerDerive.sanitize(:downcase)
      # => "hello"
  """

  @control_chars ~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/
  @zero_width_chars ~r/[\x{200B}-\x{200D}\x{FEFF}\x{2060}]/u

  @cache_key {__MODULE__, :fallback_module}

  @spec call({atom(), any()}, list(any())) :: {any(), any()}
  def call({field, input}, nil), do: {field, input}

  def call({field, input}, actions) do
    converted_input = Enum.reduce(actions, input, fn op, acc -> sanitize(acc, op) end)
    {field, converted_input}
  end

  @spec sanitize(any(), atom() | tuple()) :: any()
  def sanitize(input, :trim) do
    if is_binary(input), do: String.trim(input), else: input
  end

  def sanitize(input, :upcase) do
    if is_binary(input), do: String.upcase(input), else: input
  end

  def sanitize(input, :downcase) do
    if is_binary(input), do: String.downcase(input), else: input
  end

  def sanitize(input, :capitalize) do
    if is_binary(input), do: String.capitalize(input), else: input
  end

  if Code.ensure_loaded?(HtmlSanitizeEx) do
    def sanitize(input, :basic_html) when is_binary(input), do: HtmlSanitizeEx.basic_html(input)

    def sanitize(input, :html5) when is_binary(input), do: HtmlSanitizeEx.html5(input)

    def sanitize(input, :markdown_html) when is_binary(input),
      do: HtmlSanitizeEx.markdown_html(input)

    def sanitize(input, :strip_tags) when is_binary(input), do: HtmlSanitizeEx.strip_tags(input)

    def sanitize(input, {:tag, type}) when is_binary(input) do
      input
      |> sanitize(:trim)
      |> sanitize(if(is_binary(type), do: String.to_atom(type), else: type))
      |> sanitize(:trim)
    end

    def sanitize(input, :string_float) when is_binary(input) do
      input
      |> sanitize(:strip_tags)
      |> Float.parse()
      |> case do
        :error -> 0.0
        {converted_float, _} -> converted_float
      end
    rescue
      _ -> 0.0
    end

    def sanitize(input, :string_integer) when is_binary(input) do
      input
      |> sanitize(:strip_tags)
      |> Integer.parse()
      |> case do
        :error -> 0
        {converted_integer, _} -> converted_integer
      end
    rescue
      _ -> 0
    end
  else
    def sanitize(input, :string_float) when is_binary(input) do
      Float.parse(input)
      |> case do
        :error -> 0.0
        {converted_float, _} -> converted_float
      end
    rescue
      _ -> 0.0
    end

    def sanitize(input, :string_integer) when is_binary(input) do
      Integer.parse(input)
      |> case do
        :error -> 0
        {converted_integer, _} -> converted_integer
      end
    rescue
      _ -> 0
    end
  end

  def sanitize(input, :uniq) when is_list(input), do: Enum.uniq(input)
  def sanitize(input, :uniq), do: input

  def sanitize(input, :compact) when is_list(input), do: Enum.reject(input, &is_nil/1)
  def sanitize(input, :compact), do: input

  def sanitize(input, :reject_empty) when is_list(input) do
    Enum.reject(input, fn
      nil -> true
      "" -> true
      [] -> true
      %{} = m when map_size(m) == 0 -> true
      _ -> false
    end)
  end

  def sanitize(input, :reject_empty), do: input

  def sanitize(input, :sort) when is_list(input), do: Enum.sort(input)
  def sanitize(input, :sort), do: input

  def sanitize(input, :squish) when is_binary(input),
    do: input |> String.split() |> Enum.join(" ")

  def sanitize(input, :squish), do: input

  def sanitize(input, :no_control) when is_binary(input),
    do: String.replace(input, @control_chars, "")

  def sanitize(input, :no_control), do: input

  def sanitize(input, :no_zero_width) when is_binary(input),
    do: String.replace(input, @zero_width_chars, "")

  def sanitize(input, :no_zero_width), do: input

  def sanitize(input, {:clamp, [min, max]})
      when is_number(input) and is_number(min) and is_number(max) do
    cond do
      input < min -> min
      input > max -> max
      true -> input
    end
  end

  def sanitize(input, {:clamp, _}), do: input

  def sanitize(nil, {:default_when_nil, value}), do: value
  def sanitize(input, {:default_when_nil, _}), do: input

  def sanitize(nil, {:default_when_empty, value}), do: value
  def sanitize("", {:default_when_empty, value}), do: value
  def sanitize([], {:default_when_empty, value}), do: value
  def sanitize(%{} = m, {:default_when_empty, value}) when map_size(m) == 0, do: value
  def sanitize(input, {:default_when_empty, _}), do: input

  def sanitize(input, {:each, inner}) when is_list(input) and is_list(inner),
    do: Enum.map(input, &apply_each_sanitize(&1, inner))

  def sanitize(input, %{each: inner}) when is_list(input) and is_list(inner),
    do: Enum.map(input, &apply_each_sanitize(&1, inner))

  def sanitize(input, {:each, _}), do: input
  def sanitize(input, %{each: _}), do: input

  def sanitize(input, action) do
    case GuardedStruct.Derive.Extension.dispatch_sanitize(input, action) do
      :__not_found__ -> fallback_dispatch(input, action)
      result -> result
    end
  rescue
    _ -> input
  end

  defp apply_each_sanitize(value, inner_ops),
    do: Enum.reduce(inner_ops, value, fn op, acc -> sanitize(acc, op) end)

  defp fallback_dispatch(input, action) do
    case fallback_module() do
      nil ->
        input

      derive_module when is_list(derive_module) ->
        custom_derive(derive_module, input, action)

      derive_module ->
        derive_module.sanitize(input, action)
    end
  end

  defp fallback_module do
    raw = Application.get_env(:guarded_struct, :sanitize_derive)

    case :persistent_term.get(@cache_key, :__miss__) do
      {^raw, cached} ->
        cached

      _ ->
        :persistent_term.put(@cache_key, {raw, raw})
        raw
    end
  end

  @doc false
  def clear_fallback_cache, do: :persistent_term.erase(@cache_key)

  defp custom_derive(derive_list, input, action) do
    Enum.reduce_while(derive_list, nil, fn item, _acc ->
      case validate_pattern(item, input, action) do
        nil -> {:cont, input}
        ouput -> {:halt, if(is_nil(ouput), do: input, else: ouput)}
      end
    end)
  end

  @doc """
  Apply a user-defined sanitizer module's `sanitize/2` callback. The
  callback receives the `value` first and the op atom second.
  """
  @spec validate_pattern(module(), any(), atom()) :: any()
  def validate_pattern(module, input, action) do
    apply(module, :sanitize, [input, action])
  rescue
    _ -> nil
  end
end
