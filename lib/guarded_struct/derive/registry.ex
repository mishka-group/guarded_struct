defmodule GuardedStruct.Derive.Registry do
  @moduledoc false

  @validate_ops MapSet.new([
                  :string,
                  :integer,
                  :list,
                  :atom,
                  :bitstring,
                  :boolean,
                  :exception,
                  :float,
                  :function,
                  :map,
                  :nil_value,
                  :not_nil_value,
                  :number,
                  :pid,
                  :port,
                  :reference,
                  :struct,
                  :tuple,
                  :not_empty,
                  :not_flatten_empty,
                  :not_flatten_empty_item,
                  :queue,
                  :max_len,
                  :min_len,
                  :url,
                  :tell,
                  :geo_url,
                  :email,
                  :email_r,
                  :location,
                  :string_boolean,
                  :datetime,
                  :range,
                  :date,
                  :regex,
                  :ipv4,
                  :not_empty_string,
                  :uuid,
                  :username,
                  :full_name,
                  :enum,
                  :equal,
                  :custom,
                  :either,
                  :string_float,
                  :string_integer,
                  :some_string_float,
                  :some_string_integer
                ])

  @sanitize_ops MapSet.new([
                  :trim,
                  :upcase,
                  :downcase,
                  :capitalize,
                  :basic_html,
                  :html5,
                  :markdown_html,
                  :strip_tags,
                  :tag,
                  :string_float,
                  :string_integer
                ])

  def validate_ops, do: @validate_ops
  def sanitize_ops, do: @sanitize_ops

  def known_validate?(name) when is_atom(name), do: MapSet.member?(@validate_ops, name)
  def known_sanitize?(name) when is_atom(name), do: MapSet.member?(@sanitize_ops, name)
end
