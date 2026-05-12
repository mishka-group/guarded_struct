defmodule GuardedStructFixtures.RecordsTest do
  @moduledoc """
  Comprehensive tests for `GuardedStructFixtures.Records` —
  Erlang Record support via `validate(record)` and `validate(record=Tag)`.

  Strategy: full equality assertions everywhere. Happy paths use `==` on
  the entire returned struct (records are just tagged tuples, so equality
  is straightforward). Failure paths use `==` on the exact error list to
  lock the error shape.

  Sections:
    1. Record fundamentals — confirm what `Record.defrecord` produces
    2. validate(record=user) happy paths
    3. validate(record=user) failure paths (wrong tag, non-tuple, etc.)
    4. validate(record) (no tag) — any tagged tuple
    5. event_kind enum tests
    6. Missing required fields
    7. Multi-error aggregation
    8. Edge cases (default fields, nested records, large records)
    9. Introspection / module surface
  """

  use ExUnit.Case, async: true

  require Record
  require GuardedStructFixtures.Records
  alias GuardedStructFixtures.Records

  # ============================================================
  # 1. Record fundamentals — what defrecord actually produces
  # ============================================================
  describe "Record fundamentals (what the Record module gives us)" do
    test "Records.user(...) is just a tagged tuple — Record.is_record/1 confirms" do
      # The macro `Records.user/1` expands to a plain tuple literal whose
      # first element is the atom `:user`. This is what Erlang/OTP code
      # passes around when it talks about "records".
      rec = Records.user(name: "Alice", age: 30)

      assert rec == {:user, "Alice", 30}
      assert Record.is_record(rec)
      assert Record.is_record(rec, :user)
      refute Record.is_record(rec, :address)
    end

    test "Records.user/0 returns a record with all defaults (nil)" do
      # Record.defrecord(:user, ..., name: nil, age: nil) makes nil the
      # default for omitted keys.
      assert Records.user() == {:user, nil, nil}
      assert Records.user(name: "X") == {:user, "X", nil}
      assert Records.user(age: 99) == {:user, nil, 99}
    end

    test "Records.address has 3 fields — defrecord arity matches" do
      assert Records.address() == {:address, nil, nil, nil}

      assert Records.address(street: "Main", city: "NYC", zip: "10001") ==
               {:address, "Main", "NYC", "10001"}
    end

    test "records of different tags carry different tags at position 0" do
      # The fundamental difference: tag = first element. That's what
      # `validate(record=Tag)` checks at runtime.
      u = Records.user(name: "x", age: nil)
      a = Records.address(street: "x", city: nil, zip: nil)

      assert elem(u, 0) == :user
      assert elem(a, 0) == :address
      assert Record.is_record(u, :user)
      assert Record.is_record(a, :address)
      refute Record.is_record(u, :address)
      refute Record.is_record(a, :user)
    end
  end

  # ============================================================
  # 2. validate(record=user) — happy paths (full struct ==)
  # ============================================================
  describe "validate(record=user) happy paths (full == on the struct)" do
    test "minimal valid input — full struct equality" do
      rec = Records.user(name: "Alice", age: 30)

      assert Records.UserEvent.builder(%{event_kind: :created, user: rec}) ==
               {:ok,
                %Records.UserEvent{
                  event_kind: :created,
                  user: {:user, "Alice", 30},
                  trace: nil
                }}
    end

    test "all-defaults user record (all fields nil) still passes" do
      # The :record validator checks tagged-tuple shape, NOT the inner
      # field values. So a fully-nil-filled user record is still a valid
      # :user record.
      rec = Records.user()

      assert Records.UserEvent.builder(%{event_kind: :updated, user: rec}) ==
               {:ok,
                %Records.UserEvent{
                  event_kind: :updated,
                  user: {:user, nil, nil},
                  trace: nil
                }}
    end

    test "raw tagged tuple (not built via macro) also accepted — same shape" do
      # Macros are syntactic sugar — what matters is the resulting tuple
      # shape. A hand-built `{:user, ..., ...}` tuple is byte-identical.
      raw = {:user, "Bob", 25}
      built = Records.user(name: "Bob", age: 25)

      assert raw == built

      assert Records.UserEvent.builder(%{event_kind: :created, user: raw}) ==
               {:ok,
                %Records.UserEvent{
                  event_kind: :created,
                  user: raw,
                  trace: nil
                }}
    end

    test "all three event_kind atoms work end-to-end with full equality" do
      rec = Records.user(name: "X", age: 1)

      for kind <- [:created, :updated, :deleted] do
        assert Records.UserEvent.builder(%{event_kind: kind, user: rec}) ==
                 {:ok,
                  %Records.UserEvent{
                    event_kind: kind,
                    user: {:user, "X", 1},
                    trace: nil
                  }}
      end
    end
  end

  # ============================================================
  # 3. validate(record=user) — failure paths (exact error shape)
  # ============================================================
  describe "validate(record=user) failure paths (exact error structure)" do
    test "wrong tag (:address record) → :record action error" do
      # ERROR REASON: `:user` field's derive is `validate(record=user)`.
      # An `:address` record has the wrong tag at position 0.
      bad = Records.address(street: "Main", city: "NYC", zip: "10001")

      assert Records.UserEvent.builder(%{event_kind: :created, user: bad}) ==
               {:error,
                [
                  %{
                    message: "The user field is not a valid Erlang record (a tagged tuple).",
                    field: :user,
                    action: :record
                  }
                ]}
    end

    test "non-tuple (string) → :record error" do
      # The validator's error message is the same for "not a record" and
      # "wrong tag" — both fall under :record action.
      assert Records.UserEvent.builder(%{event_kind: :created, user: "not a tuple"}) ==
               {:error,
                [
                  %{
                    message: "The user field is not a valid Erlang record (a tagged tuple).",
                    field: :user,
                    action: :record
                  }
                ]}
    end

    test "non-tuple (map) → :record error" do
      assert Records.UserEvent.builder(%{event_kind: :created, user: %{name: "x"}}) ==
               {:error,
                [
                  %{
                    message: "The user field is not a valid Erlang record (a tagged tuple).",
                    field: :user,
                    action: :record
                  }
                ]}
    end

    test "non-tuple (atom) → :record error" do
      # ERROR REASON: an atom (e.g. `:user`) is NOT a tuple even though the
      # tag name matches — record validation requires tuple shape.
      assert Records.UserEvent.builder(%{event_kind: :created, user: :user}) ==
               {:error,
                [
                  %{
                    message: "The user field is not a valid Erlang record (a tagged tuple).",
                    field: :user,
                    action: :record
                  }
                ]}
    end

    test "empty tuple `{}` → :record error (no tag)" do
      assert Records.UserEvent.builder(%{event_kind: :created, user: {}}) ==
               {:error,
                [
                  %{
                    message: "The user field is not a valid Erlang record (a tagged tuple).",
                    field: :user,
                    action: :record
                  }
                ]}
    end

    test "tuple with string-first-element → :record error (tag must be atom)" do
      # ERROR REASON: a record's tag MUST be an atom. A tuple whose first
      # element is a string is rejected even if shape-similar.
      assert Records.UserEvent.builder(%{event_kind: :created, user: {"user", "Alice", 30}}) ==
               {:error,
                [
                  %{
                    message: "The user field is not a valid Erlang record (a tagged tuple).",
                    field: :user,
                    action: :record
                  }
                ]}
    end
  end

  # ============================================================
  # 4. validate(record) — any tag accepted on :trace
  # ============================================================
  describe "validate(record) — no tag constraint (the :trace field)" do
    test "accepts a :user record on :trace (no specific tag required)" do
      rec = Records.user(name: "Alice", age: 30)
      trace = Records.user(name: "Bob", age: 25)

      assert Records.UserEvent.builder(%{event_kind: :created, user: rec, trace: trace}) ==
               {:ok,
                %Records.UserEvent{
                  event_kind: :created,
                  user: {:user, "Alice", 30},
                  trace: {:user, "Bob", 25}
                }}
    end

    test "accepts ANY tagged tuple on :trace — custom tag works" do
      rec = Records.user(name: "X", age: 1)
      trace = {:custom_tag, "any", "payload", :here}

      assert Records.UserEvent.builder(%{event_kind: :created, user: rec, trace: trace}) ==
               {:ok,
                %Records.UserEvent{
                  event_kind: :created,
                  user: {:user, "X", 1},
                  trace: {:custom_tag, "any", "payload", :here}
                }}
    end

    test "trace defaults to nil when omitted (it's not enforced)" do
      rec = Records.user(name: "X", age: 1)

      assert Records.UserEvent.builder(%{event_kind: :created, user: rec}) ==
               {:ok,
                %Records.UserEvent{
                  event_kind: :created,
                  user: {:user, "X", 1},
                  trace: nil
                }}
    end

    test ":trace non-tuple (map) → :record error" do
      # ERROR REASON: `validate(record)` (no tag) still requires the value
      # to be a tagged tuple. A map fails the tuple check.
      rec = Records.user(name: "X", age: 1)

      assert Records.UserEvent.builder(%{event_kind: :created, user: rec, trace: %{}}) ==
               {:error,
                [
                  %{
                    message: "The trace field is not a valid Erlang record (a tagged tuple).",
                    field: :trace,
                    action: :record
                  }
                ]}
    end

    test ":trace non-tuple (string) → :record error" do
      rec = Records.user(name: "X", age: 1)

      assert Records.UserEvent.builder(%{event_kind: :created, user: rec, trace: "anywhere"}) ==
               {:error,
                [
                  %{
                    message: "The trace field is not a valid Erlang record (a tagged tuple).",
                    field: :trace,
                    action: :record
                  }
                ]}
    end
  end

  # ============================================================
  # 5. event_kind enum tests (full error shape)
  # ============================================================
  describe "event_kind enum (validate(enum=Atom[...]))" do
    test "rejects unknown atom :exploded → exact :enum error" do
      # ERROR REASON: derive enum=Atom[created::updated::deleted] only
      # accepts those three. :exploded is not in the set.
      rec = Records.user(name: "X", age: 1)

      assert Records.UserEvent.builder(%{event_kind: :exploded, user: rec}) ==
               {:error,
                [
                  %{
                    message: "Your sent data form event_kind field is not in the allowed list",
                    field: :event_kind,
                    action: :enum
                  }
                ]}
    end

    test "rejects string (not atom) → :enum error" do
      # ERROR REASON: enum=Atom[...] requires the value to be an atom.
      # "created" (string) is not an atom.
      rec = Records.user(name: "X", age: 1)

      assert Records.UserEvent.builder(%{event_kind: "created", user: rec}) ==
               {:error,
                [
                  %{
                    message: "Your sent data form event_kind field is not in the allowed list",
                    field: :event_kind,
                    action: :enum
                  }
                ]}
    end
  end

  # ============================================================
  # 6. Missing required fields
  # ============================================================
  describe "missing required fields" do
    test "missing :event_kind → :required_fields map (not a list)" do
      # ERROR REASON: orchestration-layer required-fields error returns
      # a MAP (not a list-of-maps). Same shape as forms_test confirms.
      rec = Records.user(name: "X", age: 1)

      assert Records.UserEvent.builder(%{user: rec}) ==
               {:error,
                %{
                  message: "Please submit required fields.",
                  fields: [:event_kind],
                  action: :required_fields
                }}
    end

    test "missing :user → :required_fields map" do
      assert Records.UserEvent.builder(%{event_kind: :created}) ==
               {:error,
                %{
                  message: "Please submit required fields.",
                  fields: [:user],
                  action: :required_fields
                }}
    end

    test "missing BOTH enforce'd fields → both listed in one :required_fields error" do
      assert {:error, %{action: :required_fields, fields: fields}} =
               Records.UserEvent.builder(%{})

      assert Enum.sort(fields) == [:event_kind, :user]
    end
  end

  # ============================================================
  # 7. Multi-error aggregation
  # ============================================================
  describe "multi-error aggregation" do
    test "bad event_kind + wrong record tag → BOTH errors collected" do
      # Confirms the runtime aggregates errors across stage 10's two-pass
      # derive — :user (validate(record=user)) AND :event_kind (enum) both fail.
      bad_rec = Records.address(street: "x", city: "y", zip: "z")

      assert Records.UserEvent.builder(%{event_kind: :exploded, user: bad_rec}) ==
               {:error,
                [
                  %{
                    message: "The user field is not a valid Erlang record (a tagged tuple).",
                    field: :user,
                    action: :record
                  },
                  %{
                    message: "Your sent data form event_kind field is not in the allowed list",
                    field: :event_kind,
                    action: :enum
                  }
                ]}
    end

    test "all-three derive failures (user, trace, event_kind) → 3 errors" do
      assert {:error, errs} =
               Records.UserEvent.builder(%{
                 event_kind: :exploded,
                 user: "bad",
                 trace: "also bad"
               })

      assert is_list(errs)
      # Three distinct errors aggregated:
      actions = Enum.map(errs, & &1.action) |> Enum.sort()
      assert actions == [:enum, :record, :record]

      fields = Enum.map(errs, & &1.field) |> Enum.sort()
      assert fields == [:event_kind, :trace, :user]
    end
  end

  # ============================================================
  # 8. Edge cases
  # ============================================================
  describe "edge cases" do
    test "records with complex / nested field values pass through unchanged" do
      # Record fields can be ANYTHING — maps, lists, other records.
      # The :record validator checks ONLY the tagged-tuple shape, not
      # the inner field types.
      rec = Records.user(name: %{first: "Ada", last: "Lovelace"}, age: [1, 8, 1, 5])

      assert Records.UserEvent.builder(%{event_kind: :created, user: rec}) ==
               {:ok,
                %Records.UserEvent{
                  event_kind: :created,
                  user: {:user, %{first: "Ada", last: "Lovelace"}, [1, 8, 1, 5]},
                  trace: nil
                }}
    end

    test "trace field can be a record nested in a record (tagged tuple of tagged tuple)" do
      rec = Records.user(name: "Alice", age: 30)
      nested = {:outer, {:inner, :data}, "more"}

      assert Records.UserEvent.builder(%{event_kind: :created, user: rec, trace: nested}) ==
               {:ok,
                %Records.UserEvent{
                  event_kind: :created,
                  user: {:user, "Alice", 30},
                  trace: {:outer, {:inner, :data}, "more"}
                }}
    end

    test "record values survive Map.from_struct round-trip (no transformation)" do
      # Locks the "transparent passthrough" contract — records aren't
      # re-encoded or transformed in any way by GuardedStruct.
      {:ok, event} =
        Records.UserEvent.builder(%{
          event_kind: :created,
          user: Records.user(name: "X", age: 1)
        })

      assert event.user == Records.user(name: "X", age: 1)
      assert event.user == {:user, "X", 1}
      assert Record.is_record(event.user, :user)
    end

    test "post-build record can be pattern-matched with the Record macro" do
      {:ok, event} =
        Records.UserEvent.builder(%{
          event_kind: :created,
          user: Records.user(name: "Alice", age: 30)
        })

      # Use the generated macro to deconstruct — confirms the value
      # survives the build pipeline intact.
      assert Records.user(name: name, age: age) = event.user
      assert name == "Alice"
      assert age == 30
    end
  end

  # ============================================================
  # 9. Module surface / introspection
  # ============================================================
  describe "UserEvent module introspection" do
    test "keys/0 lists all three fields in declaration order" do
      assert Records.UserEvent.keys() == [:event_kind, :user, :trace]
    end

    test "enforce_keys/0 lists :event_kind and :user only (:trace is optional)" do
      assert Enum.sort(Records.UserEvent.enforce_keys()) == [:event_kind, :user]
    end

    test "__information__/0 reports the module metadata correctly" do
      info = Records.UserEvent.__information__()
      assert info.module == Records.UserEvent
      assert info.keys == [:event_kind, :user, :trace]
      assert Enum.sort(info.enforce_keys) == [:event_kind, :user]
      assert info.conditional_keys == []
    end

    test "__fields__/0 carries the derive ops for each record-typed field" do
      fields = Records.UserEvent.__fields__()

      user_meta = Enum.find(fields, &(&1.name == :user))
      assert user_meta.derive == "validate(record=user)"
      # Parsed op is the tuple form {:record, "user"}.
      assert %{validate: [{:record, "user"}]} = user_meta.__derive_ops__

      trace_meta = Enum.find(fields, &(&1.name == :trace))
      assert trace_meta.derive == "validate(record)"
      # No tag → just the bare atom.
      assert %{validate: [:record]} = trace_meta.__derive_ops__
    end
  end
end
