defmodule GuardedStruct.AtomicClassifier do
  @moduledoc """
  Classifies a single GuardedStruct derive op as either atomic-SQL safe
  or unsafe (with a human-readable reason).

  ## How to extend

  To declare a NEW op safe for atomic mode, add a clause near the top of
  this file:

      def classify_op({:validate, :my_new_op}), do: :safe

  To mark an op UNSAFE with a specific reason (e.g. requires network I/O,
  arbitrary Elixir, etc.), add a clause near its category:

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

  # ────────────────────────────────────────────────────────────────────
  # Sanitize ops — all built-ins are atomic-safe because they run in the
  # before_action Elixir hook, BEFORE the atomic SQL fires. They never
  # touch the data layer's atomic semantics.
  #
  # The unsafe sanitize cases are user-defined Derive.Extension ops —
  # we can't statically guarantee what they do, so they're rejected.
  # ────────────────────────────────────────────────────────────────────

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

  def classify_op({:sanitize, op}) do
    {:unsafe,
     "sanitize(#{op}) is not a built-in op — it must come from a custom " <>
       "Derive.Extension and runs arbitrary Elixir code that the verifier " <>
       "can't classify"}
  end

  # ────────────────────────────────────────────────────────────────────
  # Validate ops — type checks. All translate cleanly to data-layer
  # type predicates (`is_binary`, `is_integer`, jsonb_typeof, etc.).
  # ────────────────────────────────────────────────────────────────────

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

  # ────────────────────────────────────────────────────────────────────
  # Validate ops — emptiness/length checks. Translate to `<> ''` and
  # `length()` SQL.
  # ────────────────────────────────────────────────────────────────────

  def classify_op({:validate, :not_empty}), do: :safe
  def classify_op({:validate, :not_empty_string}), do: :safe
  def classify_op({:validate, :not_flatten_empty_item}), do: :safe
  def classify_op({:validate, {:max_len, _}}), do: :safe
  def classify_op({:validate, {:min_len, _}}), do: :safe

  # ────────────────────────────────────────────────────────────────────
  # Validate ops — comparison checks.
  # ────────────────────────────────────────────────────────────────────

  def classify_op({:validate, {:max, _}}), do: :safe
  def classify_op({:validate, {:min, _}}), do: :safe
  def classify_op({:validate, {:equal, _}}), do: :safe

  # ────────────────────────────────────────────────────────────────────
  # Validate ops — regex / pattern matching. The `_r` suffix means
  # regex-only (no DNS), which most DBs can do via `~` or `LIKE`.
  # ────────────────────────────────────────────────────────────────────

  def classify_op({:validate, :uuid}), do: :safe
  def classify_op({:validate, :email_r}), do: :safe
  def classify_op({:validate, :url_r}), do: :safe
  def classify_op({:validate, :ipv4}), do: :safe
  def classify_op({:validate, :ipv6}), do: :safe
  def classify_op({:validate, :string_boolean}), do: :safe
  def classify_op({:validate, {:regex, _}}), do: :safe

  # ────────────────────────────────────────────────────────────────────
  # Validate ops — date/time. ISO-8601 parse can be a DB function.
  # ────────────────────────────────────────────────────────────────────

  def classify_op({:validate, :datetime}), do: :safe
  def classify_op({:validate, :date}), do: :safe
  def classify_op({:validate, :time}), do: :safe

  # ────────────────────────────────────────────────────────────────────
  # Validate ops — set membership.
  # ────────────────────────────────────────────────────────────────────

  def classify_op({:validate, {:enum, _}}), do: :safe

  # ────────────────────────────────────────────────────────────────────
  # Validate ops — EXPLICITLY UNSAFE. These need network I/O or external
  # processes that no SQL engine can do during a transaction.
  # ────────────────────────────────────────────────────────────────────

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

  # ────────────────────────────────────────────────────────────────────
  # Catch-all — anything we didn't enumerate is unsafe by default.
  # Contributors who add a new built-in op should add a `:safe` clause
  # above; otherwise it falls through to here.
  # ────────────────────────────────────────────────────────────────────

  def classify_op({:validate, op}) when is_atom(op) do
    {:unsafe,
     "validate(#{op}) is not in the atomic-safe registry. Likely a custom " <>
       "op from GuardedStruct.Derive.Extension or a new built-in not yet " <>
       "classified. Add a `def classify_op({:validate, :#{op}}), do: :safe` " <>
       "clause in GuardedStruct.AtomicClassifier if it's SQL-translatable"}
  end

  def classify_op({:validate, {op, _arg}}) when is_atom(op) do
    {:unsafe,
     "validate(#{op}=...) is not in the atomic-safe registry. See note " <>
       "for adding a classifier clause"}
  end

  def classify_op(other) do
    {:unsafe, "unrecognized op shape: #{inspect(other)}"}
  end
end
