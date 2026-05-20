defmodule GuardedStruct.Derive.ValidationDerive do
  alias GuardedStruct.Helper.Extra
  import GuardedStruct.Messages, only: [translated_message: 2]

  @family_alphabet Enum.concat([?a..?z, ~c" "])

  @slug_regex ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/
  @hostname_regex ~r/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/
  @hex_color_regex ~r/^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{3})$/
  @semver_regex ~r/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/

  @spec call({atom(), any()}, list(any()), String.t()) :: {any(), any()}
  def call({_field, input}, nil, _hint), do: {input, []}

  def call({field, input}, actions, hint) do
    validated = Enum.map(actions, &validate(&1, input, field))

    validated_errors =
      Enum.reduce(validated, [], fn map, acc ->
        if is_tuple(map) and elem(map, 0) == :error do
          converted_map = %{field: field, action: elem(map, 2), message: elem(map, 3)}

          converted_map =
            if(!is_nil(hint) and hint != [],
              do: Map.merge(converted_map, %{__hint__: hint}),
              else: converted_map
            )

          map_list =
            case map do
              {:error, _, _, _} ->
                [converted_map]

              {:error, _, _, _, :halt} ->
                [Map.merge(converted_map, %{status: :halt})]
            end

          map_list ++ acc
        else
          acc
        end
      end)

    {List.first(validated), validated_errors}
  end

  @spec validate(atom() | tuple(), any(), atom()) :: any()

  type_predicates = [
    string: :is_binary,
    integer: :is_integer,
    list: :is_list,
    atom: :is_atom,
    bitstring: :is_bitstring,
    boolean: :is_boolean,
    exception: :is_exception,
    float: :is_float,
    function: :is_function,
    map: :is_map,
    nil_value: :is_nil,
    number: :is_number,
    pid: :is_pid,
    port: :is_port,
    reference: :is_reference,
    struct: :is_struct,
    tuple: :is_tuple
  ]

  for {op, pred_name} <- type_predicates do
    def validate(unquote(op), input, field) do
      is_type(field, unquote(pred_name)(input), unquote(op), input)
    end
  end

  def validate(:not_nil_value, input, field) do
    is_type(field, not is_nil(input), :not_nil_value, input)
  end

  def validate(:not_empty, input, field) when is_binary(input) do
    if input == "",
      do: {:error, field, :not_empty, translated_message(:not_empty_binary, field)},
      else: input
  end

  def validate(:not_empty, input, field) when is_list(input) do
    if input == [],
      do: {:error, field, :not_empty, translated_message(:not_empty_list, field)},
      else: input
  end

  def validate(:not_empty, input, field) when is_map(input) do
    if input == %{},
      do: {:error, field, :not_empty, translated_message(:not_empty_map, field)},
      else: input
  end

  def validate(:not_empty, _, field),
    do: {:error, field, :not_empty, translated_message(:not_empty, field)}

  def validate(:not_flatten_empty, input, field) when is_list(input) do
    if List.flatten(input) == [],
      do: {:error, field, :not_flatten_empty, translated_message(:not_flatten_empty, field)},
      else: input
  end

  def validate(:not_flatten_empty_item, input, field) when is_list(input) do
    case List.flatten(input) do
      [] ->
        {:error, field, :not_flatten_empty_item,
         translated_message(:not_flatten_empty_item, field)}

      _data ->
        if Enum.find(input, &(&1 == [])) do
          {:error, field, :not_flatten_empty_item,
           translated_message(:not_flatten_empty_item, field)}
        else
          input
        end
    end
  end

  def validate(:queue, input, field) do
    if :queue.is_queue(input),
      do: input,
      else: {:error, field, :queue, translated_message(:queue, field)}
  end

  def validate({:max_len, len}, input, field) when is_binary(input) do
    if String.length(input) <= len,
      do: input,
      else: {:error, field, :max_len, translated_message(:max_len_binary, {field, len})}
  end

  def validate({:max_len, len}, input, field) when is_integer(input) or is_float(input) do
    if input <= len,
      do: input,
      else: {:error, field, :max_len, translated_message(:max_len_integer, {field, len})}
  end

  def validate({:max_len, len}, %{__struct__: Range, first: _first, last: last} = input, field) do
    if is_integer(last) and last <= len,
      do: input,
      else: {:error, field, :max_len, translated_message(:max_len_range, {field, len})}
  end

  def validate({:max_len, len}, input, field) when is_list(input) do
    if length(input) <= len,
      do: input,
      else: {:error, field, :max_len, translated_message(:max_len_list, {field, len})}
  end

  def validate(:max_len, _, field) do
    {:error, field, :max_len, translated_message(:max_len, field)}
  end

  def validate({:min_len, len}, input, field) when is_binary(input) do
    if String.length(input) < len,
      do: {:error, field, :min_len, translated_message(:min_len_binary, {field, len})},
      else: input
  end

  def validate({:min_len, len}, input, field) when is_integer(input) or is_float(input) do
    if input < len,
      do: {:error, field, :min_len, translated_message(:min_len_integer, {field, len})},
      else: input
  end

  def validate({:min_len, len}, %{__struct__: Range, first: first, last: _last} = input, field) do
    if is_integer(first) and first >= len,
      do: input,
      else: {:error, field, :min_len, translated_message(:min_len_range, {field, len})}
  end

  def validate({:min_len, len}, input, field) when is_list(input) do
    if length(input) < len,
      do: {:error, field, :min_len, translated_message(:min_len_list, {field, len})},
      else: input
  end

  def validate(:min_len, _, field) do
    {:error, field, :min_len, translated_message(:min_len, field)}
  end

  def validate(:url, input, field) do
    case URI.parse(input) do
      %URI{scheme: nil} ->
        {:error, field, :url, translated_message(:url_scheme, field)}

      %URI{host: nil} ->
        {:error, field, :url, translated_message(:url_host, field)}

      %URI{port: port, scheme: scheme, host: host}
      when port in [80, 443] and scheme in ["https", "http"] ->
        case :inet.gethostbyname(Kernel.to_charlist(host)) do
          {:ok, _} ->
            input

          _ ->
            {:error, field, :url, translated_message(:url_gethostbyname, field)}
        end

      _ ->
        {:error, field, :url, translated_message(:url, field)}
    end
  rescue
    _ -> {:error, field, :url, translated_message(:url, field)}
  end

  if Code.ensure_loaded?(ExPhoneNumber) do
    def validate({:tell, country_code}, input, field) do
      case URL.new("tel:#{input}") do
        {:ok, %URL{scheme: "tel", parsed_path: %URL.Tel{tel: _tel}}} ->
          case ExPhoneNumber.parse(input, nil) do
            {:ok, %ExPhoneNumber.Model.PhoneNumber{country_code: ^country_code}} ->
              input

            _ ->
              {:error, field, :tell, translated_message(:tell, field)}
          end

        {:error, {URL.Parser.ParseError, _msg}} ->
          {:error, field, :tell, translated_message(:tell, field)}

        _ ->
          {:error, field, :tell, translated_message(:tell, field)}
      end
    rescue
      _ -> {:error, field, :tell, translated_message(:tell, field)}
    end
  end

  if Code.ensure_loaded?(URL) do
    def validate(:tell, input, field) do
      case URL.new("tel:#{input}") do
        {:ok, %URL{scheme: "tel", parsed_path: %URL.Tel{tel: tel}}} when not is_nil(tel) ->
          input

        {:error, {URL.Parser.ParseError, _msg}} ->
          {:error, field, :tell, translated_message(:tell, field)}

        _ ->
          {:error, field, :tell, translated_message(:tell, field)}
      end
    rescue
      _ ->
        {:error, field, :tell, translated_message(:tell, field)}
    end
  end

  if Code.ensure_loaded?(URL) do
    def validate(:geo_url, input, field) do
      location("geo:#{input}", field, :geo_url)
    end
  end

  if Code.ensure_loaded?(EmailChecker) do
    def validate(:email, input, field) do
      EmailChecker.valid?(input)
      |> case do
        true -> input
        _ -> {:error, field, :email, translated_message(:email, field)}
      end
    rescue
      _ -> {:error, field, :email, translated_message(:email, field)}
    end
  end

  def validate(:email_r, input, field) do
    case Regex.match?(~r/^[A-Za-z0-9\._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,6}$/, input) do
      true -> input
      _ -> {:error, field, :email_r, translated_message(:email_r, field)}
    end
  rescue
    _ -> {:error, field, :email_r, translated_message(:email_r, field)}
  end

  if Code.ensure_loaded?(URL) do
    def validate(:location, input, field) when is_binary(input) do
      converted =
        input
        |> String.split(" ")
        |> Enum.reject(&(&1 == ""))
        |> Enum.join()

      location("geo:#{converted}", field, :location)
    rescue
      _ -> {:error, field, :email, translated_message(:location, field)}
    end
  end

  def validate(:string_boolean, input, field) do
    case input in ["true", "false"] do
      true -> input
      false -> {:error, field, :string_boolean, translated_message(:string_boolean, field)}
    end
  end

  def validate(:datetime, input, field) do
    case DateTime.from_iso8601(input) do
      {:error, _msg} ->
        {:error, field, :datetime, translated_message(:datetime, field)}

      _ ->
        input
    end
  rescue
    _ ->
      {:error, field, :datetime, translated_message(:datetime, field)}
  end

  def validate(:range, input, field) do
    _ = Range.size(input)
    input
  rescue
    _ ->
      {:error, field, :range, translated_message(:range, field)}
  end

  def validate(:date, input, field) when is_binary(input) do
    case Date.from_iso8601(input) do
      {:error, _msg} -> {:error, field, :date, translated_message(:date_binary, field)}
      _ -> input
    end
  rescue
    _ ->
      {:error, field, :date, translated_message(:date_binary, field)}
  end

  # All the regex that you want to use should put inside '' and see the result before using.
  def validate({:regex, pattern_str}, input, field)
      when is_binary(input) and is_list(pattern_str) do
    case regex_match?(to_string(pattern_str), input) do
      true -> input
      _ -> {:error, field, :regex, translated_message(:regex, field)}
    end
  rescue
    _ -> {:error, field, :regex, translated_message(:regex, field)}
  end

  def validate({:regex, pattern_str}, input, field)
      when is_binary(input) and is_binary(pattern_str) do
    case regex_match?(pattern_str, input) do
      true -> input
      _ -> {:error, field, :regex, translated_message(:regex, field)}
    end
  rescue
    _ -> {:error, field, :regex, translated_message(:regex, field)}
  end

  def validate(:ipv4, input, field) when is_binary(input) do
    segments = String.split(input, ".")

    if length(segments) != 4 do
      {:error, field, :ipv4, translated_message(:ipv4, field)}
    else
      Enum.all?(segments, &(String.to_integer(&1) in 0..255))
      |> case do
        true -> input
        false -> {:error, field, :ipv4, translated_message(:ipv4, field)}
      end
    end
  rescue
    _ ->
      {:error, field, :ipv4, translated_message(:ipv4, field)}
  end

  def validate(:ipv4, _input, field) do
    {:error, field, :ipv4, translated_message(:ipv4, field)}
  end

  def validate(:not_empty_string, input, field) do
    if is_binary(input) and input != "" do
      input
    else
      {:error, field, :not_empty_string, translated_message(:not_empty_string, field)}
    end
  end

  def validate(:uuid, input, field) do
    uuid_regex = ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

    if is_binary(input) and Regex.match?(uuid_regex, String.downcase(input)) do
      input
    else
      {:error, field, :uuid, translated_message(:uuid, field)}
    end
  end

  def validate(:username, input, field) do
    if is_binary(input) and Extra.validated_user?(input) do
      input
    else
      {:error, field, :username, translated_message(:username, field)}
    end
  end

  def validate(:full_name, input, field) when is_binary(input) do
    formated? =
      input
      |> String.to_charlist()
      |> Enum.all?(&(&1 in @family_alphabet))

    if formated? and !String.starts_with?(input, " ") do
      input
    else
      {:error, field, :full_name, translated_message(:full_name, field)}
    end
  end

  def validate(:full_name, _input, field) do
    {:error, field, :full_name, translated_message(:full_name, field)}
  end

  def validate({:enum, list}, input, field) when is_list(list) do
    convert_enum_output(list, input, field)
  end

  def validate({:enum, "String" <> list}, input, field) when is_binary(input) do
    convert_enum(list)
    |> convert_enum_output(input, field)
  end

  def validate({:enum, "Atom" <> list}, input, field) when is_atom(input) do
    convert_enum(list)
    |> Enum.map(&String.to_atom(&1))
    |> convert_enum_output(input, field)
  end

  def validate({:enum, "Integer" <> list}, input, field) when is_integer(input) do
    convert_enum(list)
    |> Enum.map(&String.to_integer(&1))
    |> convert_enum_output(input, field)
  end

  def validate({:enum, "Float" <> list}, input, field) when is_float(input) do
    convert_enum(list)
    |> Enum.map(&String.to_float(&1))
    |> convert_enum_output(input, field)
  end

  def validate({:enum, "Map" <> list}, input, field) when is_map(input) do
    convert_enum(list)
    |> convert_enum_code_eval()
    |> convert_enum_output(input, field)
  end

  def validate({:enum, "Tuple" <> list}, input, field) when is_tuple(input) do
    convert_enum(list)
    |> convert_enum_code_eval()
    |> convert_enum_output(input, field)
  end

  def validate({:enum, _}, _input, field) do
    {:error, field, :enum, translated_message(:enum, field)}
  end

  def validate({:equal, value}, input, field) when not is_binary(value) do
    vlidate_equal(value, input, field)
  end

  def validate({:equal, "String::" <> value}, input, field) do
    vlidate_equal(value, input, field)
  end

  def validate({:equal, "Integer::" <> value}, input, field) do
    String.to_integer(value)
    |> vlidate_equal(input, field)
  end

  def validate({:equal, "Float::" <> value}, input, field) do
    String.to_float(value)
    |> vlidate_equal(input, field)
  end

  def validate({:equal, "Atom::" <> value}, input, field) do
    String.to_atom(value)
    |> vlidate_equal(input, field)
  end

  def validate({:equal, "Map::" <> value}, input, field) do
    {converted, []} = Code.eval_string(value)

    converted
    |> vlidate_equal(input, field)
  end

  def validate({:equal, "Tuple::" <> value}, input, field) do
    {converted, []} = Code.eval_string(value)

    converted
    |> vlidate_equal(input, field)
  end

  def validate({:custom, {module_list, function}}, input, field) do
    safe_module = Module.safe_concat(module_list)
    executed = apply(safe_module, function, [input])
    if is_boolean(executed) and executed, do: input, else: raise(ArgumentError, "")
  rescue
    _e ->
      {:error, field, :custom, translated_message(:custom, field)}
  end

  def validate({:custom, value}, input, field) do
    [module, function] = convert_enum(value, ",")
    safe_module = Module.safe_concat([module])
    executed = apply(safe_module, String.to_atom(function), [input])
    if is_boolean(executed) and executed, do: input, else: raise(ArgumentError, "")
  rescue
    _e ->
      {:error, field, :custom, translated_message(:custom, field)}
  end

  def validate(%{either: list}, input, field) do
    Enum.any?(list, fn item ->
      output = validate(item, input, field)
      if is_tuple(output) and elem(output, 0) == :error, do: false, else: true
    end)
    |> case do
      true ->
        input

      _ ->
        {:error, field, :either, translated_message(:either, field)}
    end
  rescue
    _ ->
      {:error, field, :either, translated_message(:either, field)}
  end

  def validate(:string_float, input, field) do
    # The is_float heare can be unnecessary, just to clear code and make "It seems to make sense"
    _ = String.to_float(input)
    input
  rescue
    _ ->
      {:error, field, :string_float, translated_message(:string_float, field)}
  end

  def validate(:string_integer, input, field) do
    # The is_integer heare can be unnecessary, just to clear code and make "It seems to make sense"
    _ = String.to_integer(input)
    input
  rescue
    _ ->
      {:error, field, :string_integer, translated_message(:string_integer, field)}
  end

  # it should be noted, the string_float can be an issue if you would not sanitize before.
  # and use the other validation like string and not empty before this validation
  def validate(:some_string_float, input, field) do
    Float.parse(input)
    |> case do
      :error ->
        {:error, field, :some_string_float, translated_message(:some_string_float, field)}

      {_converted_float, _} ->
        input
    end
  rescue
    _ ->
      {:error, field, :some_string_float, translated_message(:some_string_float, field)}
  end

  def validate(:some_string_integer, input, field) do
    Integer.parse(input)
    |> case do
      :error ->
        {:error, field, :some_string_integer, translated_message(:some_string_integer, field)}

      {_converted_integer, _} ->
        input
    end
  rescue
    _ ->
      {:error, field, :some_string_integer, translated_message(:some_string_integer, field)}
  end

  def validate(:record, input, field) do
    if record?(input),
      do: input,
      else: {:error, field, :record, translated_message(:record, field)}
  end

  def validate({:record, tag}, input, field) when is_atom(tag) do
    if record?(input) and elem(input, 0) == tag,
      do: input,
      else: {:error, field, :record, translated_message(:record, field)}
  end

  def validate({:record, tag}, input, field) when is_binary(tag) do
    validate({:record, String.to_atom(tag)}, input, field)
  end

  def validate(:slug, input, field) when is_binary(input) do
    if Regex.match?(@slug_regex, input),
      do: input,
      else: {:error, field, :slug, translated_message(:slug, field)}
  end

  def validate(:slug, _input, field),
    do: {:error, field, :slug, translated_message(:slug, field)}

  def validate(:hostname, input, field) when is_binary(input) do
    if byte_size(input) <= 253 and Regex.match?(@hostname_regex, input),
      do: input,
      else: {:error, field, :hostname, translated_message(:hostname, field)}
  end

  def validate(:hostname, _input, field),
    do: {:error, field, :hostname, translated_message(:hostname, field)}

  def validate(:port_number, input, _field)
      when is_integer(input) and input >= 1 and input <= 65535,
      do: input

  def validate(:port_number, _input, field),
    do: {:error, field, :port_number, translated_message(:port_number, field)}

  def validate(:hex_color, input, field) when is_binary(input) do
    if Regex.match?(@hex_color_regex, input),
      do: input,
      else: {:error, field, :hex_color, translated_message(:hex_color, field)}
  end

  def validate(:hex_color, _input, field),
    do: {:error, field, :hex_color, translated_message(:hex_color, field)}

  def validate(:semver, input, field) when is_binary(input) do
    if Regex.match?(@semver_regex, input),
      do: input,
      else: {:error, field, :semver, translated_message(:semver, field)}
  end

  def validate(:semver, _input, field),
    do: {:error, field, :semver, translated_message(:semver, field)}

  def validate({:optional, _inner}, nil, _field), do: nil
  def validate(%{optional: _inner}, nil, _field), do: nil

  def validate({:optional, inner}, input, field) when is_atom(inner) do
    run_optional_inner([inner], input, field)
  end

  def validate({:optional, inner}, input, field) when is_list(inner) do
    run_optional_inner(inner, input, field)
  end

  def validate(%{optional: inner}, input, field) when is_list(inner) do
    run_optional_inner(inner, input, field)
  end

  def validate({:each, inner}, input, field) when is_list(input) and is_list(inner),
    do: run_each(input, inner, field)

  def validate(%{each: inner}, input, field) when is_list(input) and is_list(inner),
    do: run_each(input, inner, field)

  def validate({:each, _}, _input, field),
    do: {:error, field, :each, translated_message(:each, field)}

  def validate(%{each: _}, _input, field),
    do: {:error, field, :each, translated_message(:each, field)}

  def validate(action, input, field) do
    case GuardedStruct.Derive.Extension.dispatch_validate(action, input, field) do
      :__not_found__ -> fallback_dispatch(action, input, field)
      result -> result
    end
  rescue
    _ ->
      {:error, field, :type, translated_message(:validate_unexpected, field)}
  end

  defp run_optional_inner(inner_ops, input, field) do
    Enum.reduce_while(inner_ops, input, fn op, _acc ->
      case validate(op, input, field) do
        {:error, _, _, _} = err -> {:halt, err}
        {:error, _, _, _, _} = err -> {:halt, err}
        _ok -> {:cont, input}
      end
    end)
  end

  defp run_each(input, inner_ops, field) do
    bad_indices =
      input
      |> Enum.with_index()
      |> Enum.reduce([], fn {elem, idx}, acc ->
        if each_element_ok?(elem, inner_ops, field), do: acc, else: [idx | acc]
      end)
      |> Enum.reverse()

    case bad_indices do
      [] ->
        input

      _ ->
        {:error, field, :each,
         translated_message(:each, field) <> " (failed indices: #{inspect(bad_indices)})"}
    end
  end

  defp each_element_ok?(elem, inner_ops, field) do
    Enum.all?(inner_ops, fn op ->
      case validate(op, elem, field) do
        {:error, _, _, _} -> false
        {:error, _, _, _, _} -> false
        _ -> true
      end
    end)
  end

  defp fallback_dispatch(action, input, field) do
    case Application.get_env(:guarded_struct, :validate_derive) do
      nil ->
        {:error, field, :type, translated_message(:validate_unexpected, field)}

      derive_module when is_list(derive_module) ->
        custom_derive(derive_module, action, input, field)

      derive_module ->
        derive_module.validate(action, input, field)
    end
  end

  if Code.ensure_loaded?(URL) do
    defp location(geo_link, field, action) do
      case URL.new(geo_link) do
        {:ok, %URL{scheme: "geo", parsed_path: %URL.Geo{lat: lat, lng: lng}}}
        when not is_nil(lat) and not is_nil(lng) ->
          geo_link

        _ ->
          {:error, field, action, translated_message(:location_url, field)}
      end
    rescue
      _ ->
        {:error, field, action, translated_message(:location_url, field)}
    end
  end

  defp record?(input) do
    is_tuple(input) and tuple_size(input) > 0 and is_atom(elem(input, 0))
  end

  defp is_type(field, status, type, input) do
    if status,
      do: input,
      else: {:error, field, type, translated_message(:is_type, {field, type})}
  end

  defp regex_match?(pattern_str, subject) do
    case Regex.compile(pattern_str) do
      {:ok, regex} -> Regex.match?(regex, subject)
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :unexpected_regex}
  end

  defp custom_derive(derive_list, action, input, field) do
    Enum.reduce_while(derive_list, nil, fn item, _acc ->
      case validate_pattern(item, action, input, field) do
        nil -> {:cont, nil}
        ouput -> {:halt, ouput}
      end
    end)
    |> case do
      nil -> {:error, field, :type, translated_message(:validate_unexpected, field)}
      data -> data
    end
  end

  defp validate_pattern(module, action, input, field) do
    apply(module, :validate, [action, input, field])
  rescue
    _ -> nil
  end

  def convert_enum(list, splitter \\ "::") do
    list
    |> String.replace(["[", "]"], "")
    |> String.split(splitter, trim: true)
    |> Enum.map(&String.trim(&1))
  end

  defp convert_enum_output(list, input, field) do
    list
    |> Enum.find(&(&1 == input))
    |> case do
      nil ->
        {:error, field, :enum, translated_message(:convert_enum_output, field)}

      data ->
        data
    end
  end

  defp convert_enum_code_eval(list) do
    list
    |> Enum.map(fn item ->
      {converted, []} = Code.eval_string(item)
      converted
    end)
  end

  defp vlidate_equal(validator, input, field) do
    if validator === input,
      do: input,
      else: {:error, field, :equal, translated_message(:equal, field)}
  end
end
