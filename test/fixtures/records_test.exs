defmodule GuardedStructFixtures.RecordsTest do
  @moduledoc """
  Tests the `GuardedStructFixtures.Records` fixture — `validate(record=Tag)`
  and `validate(record)` (any tag) on real `Record.defrecord/2` values.
  """

  use ExUnit.Case, async: true

  require GuardedStructFixtures.Records
  alias GuardedStructFixtures.Records

  describe "validate(record=user)" do
    test "accepts a record built with the matching tag" do
      rec = Records.user(name: "Alice", age: 30)

      assert {:ok, %Records.UserEvent{user: ^rec}} =
               Records.UserEvent.builder(%{event_kind: :created, user: rec})
    end

    test "rejects a record with the wrong tag" do
      bad = Records.address(street: "Main", city: "NYC")

      assert {:error, _} =
               Records.UserEvent.builder(%{event_kind: :created, user: bad})
    end
  end

  describe "validate(enum=Atom[...]) on event_kind" do
    test "rejects an unknown atom" do
      rec = Records.user(name: "Alice", age: 30)

      assert {:error, _} =
               Records.UserEvent.builder(%{event_kind: :exploded, user: rec})
    end

    test "accepts each of the listed atoms" do
      rec = Records.user(name: "X", age: 1)

      for kind <- [:created, :updated, :deleted] do
        assert {:ok, _} =
                 Records.UserEvent.builder(%{event_kind: kind, user: rec})
      end
    end
  end

  describe "validate(record) (no tag)" do
    test "accepts any tagged tuple on the :trace field" do
      rec = Records.user(name: "X", age: 1)
      trace = {:custom, "anywhere"}

      assert {:ok, ev} =
               Records.UserEvent.builder(%{event_kind: :created, user: rec, trace: trace})

      assert ev.trace == trace
    end
  end
end
