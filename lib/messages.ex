defmodule GuardedStruct.Messages do
  @moduledoc """
  This module is used to define the messages that are used in the guarded_struct library.
  You can define your own messages by creating a module that uses this module and
  implements the callbacks defined in this module.
  It can be used to define messages in multiple languages like using Gettext.

  ## Usage
  ```elixir
  defmodule GuardedStruct.Your.Messages do
    use GuardedStruct.Messages
    import MyAppWeb.Gettext

    def required_fields(), do: gettext("Please submit required fields.")
  end
  ```

  Remember to add `message_backend: GuardedStruct.Your.Messages` to your
  configuration.

  ```elixir
  config :guarded_struct, message_backend: GuardedStruct.Your.Messages
  ```
  """

  @message_backend Application.compile_env(:guarded_struct, :message_backend, __MODULE__)
  @type message :: binary()

  # GuardedStruct
  @callback required_fields() :: message()
  @callback authorized_fields() :: message()
  @callback message_exception() :: message()
  @callback message_exception(any()) :: message()
  @callback builder() :: message()
  @callback register_struct() :: message()
  @callback field(any()) :: message()
  @callback field_type(any()) :: message()
  @callback list_builder() :: message()
  @callback list_builder_field_exception() :: message()
  @callback list_builder_type() :: message()
  @callback check_dependent_keys({any(), any()}) :: message()
  @callback domain_field_status(any()) :: message()
  @callback force_domain_field_status(any()) :: message()
  # Parser
  @callback parser_field_value() :: message()
  @callback unsupported_conditional_field() :: message()
  # ValidationDerive
  @callback not_empty_binary(any()) :: message()
  @callback not_empty_list(any()) :: message()
  @callback not_empty_map(any()) :: message()
  @callback not_empty(any()) :: message()
  @callback not_flatten_empty(any()) :: message()
  @callback not_flatten_empty_item(any()) :: message()
  @callback queue(any()) :: message()
  @callback max_len_binary({any(), any()}) :: message()
  @callback max_len_integer({any(), any()}) :: message()
  @callback max_len_range({any(), any()}) :: message()
  @callback max_len_list({any(), any()}) :: message()
  @callback max_len(any()) :: message()
  @callback min_len_binary({any(), any()}) :: message()
  @callback min_len_integer({any(), any()}) :: message()
  @callback min_len_range({any(), any()}) :: message()
  @callback min_len_list({any(), any()}) :: message()
  @callback min_len(any()) :: message()
  @callback url_scheme(any()) :: message()
  @callback url_host(any()) :: message()
  @callback url_gethostbyname(any()) :: message()
  @callback url(any()) :: message()
  @callback tell(any()) :: message()
  @callback email(any()) :: message()
  @callback email_r(any()) :: message()
  @callback location(any()) :: message()
  @callback string_boolean(any()) :: message()
  @callback datetime(any()) :: message()
  @callback range(any()) :: message()
  @callback date_binary(any()) :: message()
  @callback regex(any()) :: message()
  @callback ipv4(any()) :: message()
  @callback not_empty_string(any()) :: message()
  @callback uuid(any()) :: message()
  @callback username(any()) :: message()
  @callback full_name(any()) :: message()
  @callback enum(any()) :: message()
  @callback custom(any()) :: message()
  @callback either(any()) :: message()
  @callback string_float(any()) :: message()
  @callback string_integer(any()) :: message()
  @callback some_string_float(any()) :: message()
  @callback some_string_integer(any()) :: message()
  @callback validate_unexpected(any()) :: message()
  @callback location_url(any()) :: message()
  @callback is_type({any(), any()}) :: message()
  @callback convert_enum_output(any()) :: message()
  @callback equal(any()) :: message()

  @optional_callbacks required_fields: 0,
                      authorized_fields: 0,
                      message_exception: 0,
                      message_exception: 1,
                      builder: 0,
                      register_struct: 0,
                      field: 1,
                      field_type: 1,
                      list_builder: 0,
                      list_builder_field_exception: 0,
                      list_builder_type: 0,
                      check_dependent_keys: 1,
                      domain_field_status: 1,
                      force_domain_field_status: 1,
                      parser_field_value: 0,
                      unsupported_conditional_field: 0,
                      not_empty_binary: 1,
                      not_empty_list: 1,
                      not_empty_map: 1,
                      not_empty: 1,
                      not_flatten_empty: 1,
                      not_flatten_empty_item: 1,
                      queue: 1,
                      max_len_binary: 1,
                      max_len_integer: 1,
                      max_len_range: 1,
                      max_len_list: 1,
                      max_len: 1,
                      min_len_binary: 1,
                      min_len_integer: 1,
                      min_len_range: 1,
                      min_len_list: 1,
                      min_len: 1,
                      url_scheme: 1,
                      url_host: 1,
                      url_gethostbyname: 1,
                      url: 1,
                      tell: 1,
                      email: 1,
                      email_r: 1,
                      location: 1,
                      string_boolean: 1,
                      datetime: 1,
                      range: 1,
                      date_binary: 1,
                      regex: 1,
                      ipv4: 1,
                      not_empty_string: 1,
                      uuid: 1,
                      username: 1,
                      full_name: 1,
                      enum: 1,
                      custom: 1,
                      either: 1,
                      string_float: 1,
                      string_integer: 1,
                      some_string_float: 1,
                      some_string_integer: 1,
                      validate_unexpected: 1,
                      location_url: 1,
                      is_type: 1,
                      convert_enum_output: 1,
                      equal: 1

  @doc false
  # Get idea from https://github.com/pow-auth/pow/blob/main/lib/pow/phoenix/messages.ex
  defmacro __using__(_opts) do
    quote do
      @behaviour unquote(__MODULE__)

      # GuardedStruct
      def required_fields(), do: unquote(__MODULE__).required_fields()
      def authorized_fields(), do: unquote(__MODULE__).authorized_fields()
      def message_exception(), do: unquote(__MODULE__).message_exception()
      def message_exception(exception), do: unquote(__MODULE__).message_exception(exception)
      def builder(), do: unquote(__MODULE__).builder()
      def field(name), do: unquote(__MODULE__).field(name)
      def field_type(name), do: unquote(__MODULE__).field_type(name)
      def list_builder(), do: unquote(__MODULE__).list_builder()
      def list_builder_type(), do: unquote(__MODULE__).list_builder_type()
      def check_dependent_keys(key_value), do: unquote(__MODULE__).check_dependent_keys(key_value)
      def domain_field_status(key), do: unquote(__MODULE__).domain_field_status(key)
      def force_domain_field_status(key), do: unquote(__MODULE__).force_domain_field_status(key)

      # Parser
      def unsupported_conditional_field(), do: unquote(__MODULE__).unsupported_conditional_field()
      def parser_field_value(), do: unquote(__MODULE__).parser_field_value()

      # ValidationDerive
      def not_empty_binary(field), do: unquote(__MODULE__).not_empty_binary(field)
      def not_empty_list(field), do: unquote(__MODULE__).not_empty_list(field)
      def not_empty_map(field), do: unquote(__MODULE__).not_empty_map(field)
      def not_empty(field), do: unquote(__MODULE__).not_empty(field)
      def not_flatten_empty(field), do: unquote(__MODULE__).not_flatten_empty(field)
      def not_flatten_empty_item(field), do: unquote(__MODULE__).not_flatten_empty_item(field)
      def queue(field), do: unquote(__MODULE__).queue(field)
      def max_len_binary(field), do: unquote(__MODULE__).max_len_binary(field)
      def max_len_integer(field), do: unquote(__MODULE__).max_len_integer(field)
      def max_len_range(field), do: unquote(__MODULE__).max_len_range(field)
      def max_len_list(field), do: unquote(__MODULE__).max_len_list(field)
      def max_len(field), do: unquote(__MODULE__).max_len(field)
      def min_len_binary(field), do: unquote(__MODULE__).min_len_binary(field)
      def min_len_integer(field), do: unquote(__MODULE__).min_len_integer(field)
      def min_len_range(field), do: unquote(__MODULE__).min_len_range(field)
      def min_len_list(field), do: unquote(__MODULE__).min_len_list(field)
      def min_len(field), do: unquote(__MODULE__).min_len(field)
      def url_scheme(field), do: unquote(__MODULE__).url_scheme(field)
      def url_host(field), do: unquote(__MODULE__).url_host(field)
      def url_gethostbyname(field), do: unquote(__MODULE__).url_gethostbyname(field)
      def url(field), do: unquote(__MODULE__).url(field)
      def tell(field), do: unquote(__MODULE__).tell(field)
      def email(field), do: unquote(__MODULE__).email(field)
      def email_r(field), do: unquote(__MODULE__).email_r(field)
      def location(field), do: unquote(__MODULE__).location(field)
      def string_boolean(field), do: unquote(__MODULE__).string_boolean(field)
      def datetime(field), do: unquote(__MODULE__).datetime(field)
      def range(field), do: unquote(__MODULE__).range(field)
      def date_binary(field), do: unquote(__MODULE__).date_binary(field)
      def regex(field), do: unquote(__MODULE__).regex(field)
      def ipv4(field), do: unquote(__MODULE__).ipv4(field)
      def not_empty_string(field), do: unquote(__MODULE__).not_empty_string(field)
      def uuid(field), do: unquote(__MODULE__).uuid(field)
      def username(field), do: unquote(__MODULE__).username(field)
      def full_name(field), do: unquote(__MODULE__).full_name(field)
      def enum(field), do: unquote(__MODULE__).enum(field)
      def custom(field), do: unquote(__MODULE__).custom(field)
      def either(field), do: unquote(__MODULE__).either(field)
      def string_integer(field), do: unquote(__MODULE__).string_integer(field)
      def string_float(field), do: unquote(__MODULE__).string_float(field)
      def some_string_float(field), do: unquote(__MODULE__).some_string_float(field)
      def some_string_integer(field), do: unquote(__MODULE__).some_string_integer(field)
      def validate_unexpected(field), do: unquote(__MODULE__).validate_unexpected(field)
      def location_url(field), do: unquote(__MODULE__).location_url(field)
      def is_type(field), do: unquote(__MODULE__).is_type(field)
      def convert_enum_output(field), do: unquote(__MODULE__).convert_enum_output(field)
      def equal(field), do: unquote(__MODULE__).equal(field)

      defoverridable unquote(__MODULE__)
    end
  end

  # GuardedStruct
  def required_fields(), do: "Please submit required fields."

  def authorized_fields(), do: "Unauthorized keys are present in the sent data."

  def message_exception(), do: "There is at least one validation problem with your data:"

  def message_exception(exception) do
    "There is at least one validation problem with your data: #{inspect(exception.term)}"
  end

  def builder(), do: "Your input must be a map or list of maps"

  def register_struct(),
    do:
      "Main validator is came as a tuple and includes {module, function_name}, noted the function_name should be atom."

  def field(name) do
    "the field #{inspect(name)} is already set"
  end

  def field_type(name) do
    "a field name must be an atom, got #{inspect(name)}"
  end

  def list_builder(),
    do: "Unfortunately, the appropriate settings have not been applied to the desired field."

  def list_builder_field_exception(),
    do:
      "Oh no!, We do not currently support using a normal field as a list without an extra module."

  def list_builder_type(), do: "Your input must be a list of items"

  def check_dependent_keys({key, splited_pattern}) do
    """
    The required dependency for field #{Atom.to_string(key)} has not been submitted.
    You must have field #{List.last(splited_pattern) |> Atom.to_string()} in your input
    """
  end

  def domain_field_status(key), do: "Based on field #{key} input you have to send authorized data"

  def force_domain_field_status(key),
    do: "Based on field #{key} input you have to send authorized data and required key"

  # Parser
  def unsupported_conditional_field() do
    """
    \n ----------------------------------------------------------\n
    Unfortunately, this macro does not support the nested mode in the conditional_field macro.
    If you can add this feature I would be very happy to send a PR.
    More information: https://github.com/mishka-group/guarded_struct/issues/7
    Parent Issue: https://github.com/mishka-group/guarded_struct/issues/8
    \n ----------------------------------------------------------\n
    """
  end

  def parser_field_value(),
    do:
      "Oh no!, I think you have not made all the subfields of a conditional field to the same name"

  # ValidationDerive
  def not_empty_binary(field), do: "The #{field} field must not be empty"
  def not_empty_list(field), do: "The #{field} field must not be empty"
  def not_empty_map(field), do: "The #{field} field must not be empty"

  def not_empty(field),
    do:
      "Invalid NotEmpty format in the #{field} field, you must pass data which is string, list or map."

  def not_flatten_empty(field), do: "The #{field} field must not be empty"

  def not_flatten_empty_item(field), do: "The #{field} field item must not be empty"

  def queue(field), do: "The #{field} field must be a queue format"

  def max_len_binary({field, len}),
    do:
      "The maximum number of characters in the #{field} field is #{len} and you have sent more than this number of entries"

  def max_len_integer({field, len}),
    do:
      "The maximum number the #{field} field is #{len} and you have sent more than this number of entries"

  def max_len_range({field, len}),
    do:
      "The minimum range the #{field} field is #{len} and you have sent less than this number of entries"

  def max_len_list({field, len}),
    do:
      "The maximum number of items in the #{field} field list is #{len} and you have sent more than this number of entries"

  def max_len(field),
    do:
      "Invalid Max length format in the #{field} field, you must pass data which is integer, range or string."

  def min_len_binary({field, len}),
    do:
      "The minimum number of characters in the #{field} field is #{len} and you have sent less than this number of entries"

  def min_len_integer({field, len}),
    do:
      "The minimum number the #{field} field is #{len} and you have sent less than this number of entries"

  def min_len_range({field, len}),
    do:
      "The minimum range the #{field} field is #{len} and you have sent less than this number of entries"

  def min_len_list({field, len}),
    do:
      "The minimum number of items in the #{field} field list is #{len} and you have sent less than this number of entries"

  def min_len(field),
    do:
      "Invalid Min length format in the #{field} field, you must pass data which is integer, range or string."

  def url_scheme(field), do: "Is missing a url scheme (e.g. https) in the #{field} field"

  def url_host(field), do: "Is missing a url host in the #{field} field"

  def url_gethostbyname(field), do: "Invalid url host in the #{field} field"

  def url(field), do: "Invalid url format in the #{field} field"

  def tell(field), do: "Invalid tell format in the #{field} field"

  def email(field), do: "Incorrect email in the #{field} field."

  def email_r(field), do: "Incorrect email in the #{field} field."

  def location(field), do: "Invalid location format in the #{field} field"

  def string_boolean(field), do: "Invalid boolean format in the #{field} field"

  def datetime(field), do: "Invalid DateTime format in the #{field} field"

  def range(field), do: "Invalid Range format in the #{field} field"

  def date_binary(field), do: "Invalid Date format in the #{field} field"

  def regex(field), do: "Invalid format in the #{field} field"

  def ipv4(field), do: "Invalid format in the #{field} field"

  def not_empty_string(field), do: "Invalid format in the #{field} field"

  def uuid(field), do: "Invalid UUID format in the #{field} field"

  def username(field), do: "Invalid username format in the #{field} field"

  def full_name(field), do: "Invalid family format in the #{field} field"

  def enum(field), do: "Invalid format in the #{field} field"

  def custom(field), do: "The condition for checking the #{field} field is not correct"

  def either(field), do: "None of the conditions for checking the #{field} field is not correct"

  def string_float(field), do: "The output of the #{field} field cannot be Float"

  def string_integer(field), do: "The output of the #{field} field cannot be Integer"

  def some_string_float(field), do: "The output of the #{field} field cannot be Float"

  def some_string_integer(field), do: "The output of the #{field} field cannot be Integer"

  def validate_unexpected(field), do: "Unexpected type error in #{field} field"

  def location_url(field),
    do: "Invalid geo url format in the #{field} field, you should send latitude and longitude"

  def is_type({field, type}), do: "The #{field} field must be #{type}"

  def convert_enum_output(field),
    do: "Your sent data form #{field} field is not in the allowed list"

  def equal(field), do: "Invalid value in the #{field} field"

  # Helpers
  def translated_message(fn_atom), do: apply(@message_backend, fn_atom, [])

  def translated_message(fn_atom, options), do: apply(@message_backend, fn_atom, [options])
end
