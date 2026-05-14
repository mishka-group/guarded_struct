defmodule GuardedStruct.AtomicClassifier do
  @moduledoc """
  Classifies a single GuardedStruct derive op as either atomic-SQL safe
  or unsafe (with a human-readable reason).

  To declare a NEW op safe for atomic mode, add a clause near the top of
  this file:

      def classify_op({:validate, :my_new_op}), do: :safe

  To mark an op UNSAFE with a specific reason, add a clause near its
  category:

      def classify_op({:validate, :my_dns_op}) do
        {:unsafe, "validate(my_dns_op) performs a DNS lookup — needs I/O"}
      end

  The catch-all at the bottom rejects anything not enumerated. Be
  conservative: when in doubt, an op is unsafe.

  ## Op shape

  The runtime represents derive ops as one of:

    * `{:sanitize, :trim}` — sanitize, no arg
    * `{:validate, :string}` — validate, no arg
    * `{:validate, {:max_len, 20}}` — validate, with literal arg
    * `{:validate, {enum: ["a", "b"]}}` — keyword-list arg variant
  """

  def classify_op({:sanitize, :trim}), do: :safe
  def classify_op({:sanitize, :downcase}), do: :safe
  def classify_op({:sanitize, :upcase}), do: :safe
  def classify_op({:sanitize, :capitalize}), do: :safe
  def classify_op({:sanitize, :string}), do: :safe
  def classify_op({:sanitize, :integer}), do: :safe
  def classify_op({:sanitize, :float}), do: :safe
  def classify_op({:sanitize, :strip_tags}), do: :safe
  def classify_op({:sanitize, :basic_html}), do: :safe
  def classify_op({:sanitize, :html5}), do: :safe
  def classify_op({:sanitize, :tag}), do: :safe
  def classify_op({:sanitize, {:tag, _}}), do: :safe

  def classify_op({:sanitize, op}) when is_atom(op) do
    cond do
      GuardedStruct.Derive.Registry.known_sanitize?(op) ->
        {:unsafe,
         "sanitize(#{op}) is a built-in op but not in the atomic-safe " <>
           "registry. If you've verified it's SQL-translatable, add a " <>
           "`def classify_op({:sanitize, :#{op}}), do: :safe` clause in " <>
           "GuardedStruct.AtomicClassifier"}

      true ->
        {:unsafe,
         "sanitize(#{op}) is NOT a known built-in op. Possible causes: " <>
           "(1) typo of a built-in — check spelling against `mix help " <>
           "guarded_struct` or `GuardedStruct.Derive.Registry.sanitize_ops/0`; " <>
           "(2) custom op from `GuardedStruct.Derive.Extension` — custom " <>
           "ops run arbitrary Elixir and can't be atomic-safe. Either fix " <>
           "the typo or set `atomic: false`"}
    end
  end

  def classify_op({:sanitize, op}) do
    {:unsafe, "sanitize op #{inspect(op)} has an unrecognized shape"}
  end

  def classify_op({:validate, :string}), do: :safe
  def classify_op({:validate, :integer}), do: :safe
  def classify_op({:validate, :float}), do: :safe
  def classify_op({:validate, :boolean}), do: :safe
  def classify_op({:validate, :atom}), do: :safe
  def classify_op({:validate, :list}), do: :safe
  def classify_op({:validate, :map}), do: :safe
  def classify_op({:validate, :tuple}), do: :safe
  def classify_op({:validate, :record}), do: :safe
  def classify_op({:validate, {:record, _tag}}), do: :safe

  def classify_op({:validate, :not_empty}), do: :safe
  def classify_op({:validate, :not_empty_string}), do: :safe
  def classify_op({:validate, :not_flatten_empty_item}), do: :safe
  def classify_op({:validate, {:max_len, _}}), do: :safe
  def classify_op({:validate, {:min_len, _}}), do: :safe

  def classify_op({:validate, {:max, _}}), do: :safe
  def classify_op({:validate, {:min, _}}), do: :safe
  def classify_op({:validate, {:equal, _}}), do: :safe

  def classify_op({:validate, :uuid}), do: :safe
  def classify_op({:validate, :email_r}), do: :safe
  def classify_op({:validate, :url_r}), do: :safe
  def classify_op({:validate, :ipv4}), do: :safe
  def classify_op({:validate, :ipv6}), do: :safe
  def classify_op({:validate, :string_boolean}), do: :safe
  def classify_op({:validate, {:regex, _}}), do: :safe

  def classify_op({:validate, :datetime}), do: :safe
  def classify_op({:validate, :date}), do: :safe
  def classify_op({:validate, :time}), do: :safe

  def classify_op({:validate, {:enum, _}}), do: :safe

  def classify_op({:validate, :email}) do
    {:unsafe,
     "validate(email) performs a DNS lookup via :email_checker. Use " <>
       "validate(email_r) for atomic mode (regex-only check)"}
  end

  def classify_op({:validate, :url}) do
    {:unsafe,
     "validate(url) performs DNS / port checking via :ex_url. Use " <>
       "validate(url_r) for atomic mode (regex-only check)"}
  end

  def classify_op({:validate, :geo}) do
    {:unsafe,
     "validate(geo) requires custom geo SQL functions. Not in the " <>
       "default atomic-safe registry"}
  end

  def classify_op({:validate, :location}) do
    {:unsafe,
     "validate(location) requires custom geo SQL functions. Not in the " <>
       "default atomic-safe registry"}
  end

  def classify_op({:validate, :type}) do
    {:unsafe,
     "validate(type) has variable interpretation. Use a specific type " <>
       "validator (string, integer, list, ...) for atomic mode"}
  end

  def classify_op({:validate, {:tell, _country}}) do
    {:unsafe,
     "validate(tell, country_code) may require external library lookup. " <>
       "Not in the default atomic-safe registry"}
  end

  def classify_op({:validate, op}) when is_atom(op) do
    cond do
      GuardedStruct.Derive.Registry.known_validate?(op) ->
        {:unsafe,
         "validate(#{op}) is a built-in op but not in the atomic-safe " <>
           "registry. If you've verified it's SQL-translatable, add a " <>
           "`def classify_op({:validate, :#{op}}), do: :safe` clause in " <>
           "GuardedStruct.AtomicClassifier"}

      true ->
        {:unsafe,
         "validate(#{op}) is NOT a known built-in op. Possible causes: " <>
           "(1) typo of a built-in — check spelling against " <>
           "`GuardedStruct.Derive.Registry.validate_ops/0`; " <>
           "(2) custom op from `GuardedStruct.Derive.Extension` — custom " <>
           "ops run arbitrary Elixir and can't be atomic-safe. Either fix " <>
           "the typo or set `atomic: false`"}
    end
  end

  def classify_op({:validate, {op, _arg}}) when is_atom(op) do
    cond do
      GuardedStruct.Derive.Registry.known_validate?(op) ->
        {:unsafe,
         "validate(#{op}=...) is a built-in op but not in the atomic-safe " <>
           "registry. Add a classifier clause if it's SQL-translatable"}

      true ->
        {:unsafe,
         "validate(#{op}=...) is NOT a known built-in op. Possible causes: " <>
           "typo of a built-in or custom Derive.Extension op. Either fix " <>
           "the typo or set `atomic: false`"}
    end
  end

  def classify_op(other) do
    {:unsafe, "unrecognized op shape: #{inspect(other)}"}
  end
end
