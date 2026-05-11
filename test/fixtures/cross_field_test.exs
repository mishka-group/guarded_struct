defmodule GuardedStructFixtures.CrossFieldTest do
  @moduledoc """
  Tests the `GuardedStructFixtures.CrossField` fixture — covering:

    * `AuditedEvent` — `from:`, `on:`, `auto:`, `domain:`, `authorized_fields:`
    * `StrictEvent` — the `sub_field(..., enforce: true)` enforce-cascade pattern
  """

  use ExUnit.Case, async: true

  alias GuardedStructFixtures.CrossField

  describe "AuditedEvent (from / on / auto / domain)" do
    test "happy path: from: pulls actor_id; auto: mints event_id" do
      assert {:ok, ev} =
               CrossField.AuditedEvent.builder(%{
                 actor_id: "11111111-1111-1111-1111-111111111111",
                 account_type: "enterprise",
                 requested_by: "alice",
                 event: %{name: "did the thing", kind: "billing.refund"}
               })

      assert ev.event.actor_id == ev.actor_id
      assert is_binary(ev.event.event_id)
      assert String.length(ev.event.event_id) > 10
    end

    test "on: blocks build when the depended-on path is missing" do
      assert {:error, _} =
               CrossField.AuditedEvent.builder(%{
                 account_type: "enterprise",
                 requested_by: "alice",
                 event: %{name: "x", kind: "login"}
               })
    end

    test "validate(enum=...) rejects an out-of-set kind" do
      assert {:error, _} =
               CrossField.AuditedEvent.builder(%{
                 actor_id: "11111111-1111-1111-1111-111111111111",
                 account_type: "enterprise",
                 requested_by: "alice",
                 event: %{name: "x", kind: "totally.invented"}
               })
    end

    test "domain: rejects values outside the allowed account_type set" do
      assert {:error, _} =
               CrossField.AuditedEvent.builder(%{
                 actor_id: "11111111-1111-1111-1111-111111111111",
                 account_type: "trial",
                 requested_by: "alice",
                 event: %{name: "x", kind: "login"}
               })
    end

    test "authorized_fields: true rejects unknown top-level keys" do
      assert {:error, _} =
               CrossField.AuditedEvent.builder(%{
                 actor_id: "11111111-1111-1111-1111-111111111111",
                 account_type: "free",
                 requested_by: "alice",
                 event: %{name: "x", kind: "login"},
                 hacker_added: "value"
               })
    end
  end

  describe "StrictEvent (sub_field enforce-cascade pattern)" do
    test "happy path: all enforced inner fields supplied → build succeeds" do
      assert {:ok, ev} =
               CrossField.StrictEvent.builder(%{
                 source: "api",
                 payload: %{kind: "create", body: %{user_id: 1}}
               })

      assert ev.payload.kind == "create"
      assert ev.payload.trace_id == nil
      assert ev.payload.retries == 0
    end

    test "missing :kind (cascaded enforce) → :required_fields error" do
      assert {:error, errs} =
               CrossField.StrictEvent.builder(%{
                 source: "api",
                 payload: %{body: %{x: 1}}
               })

      errs = List.wrap(errs)

      assert Enum.any?(errs, fn err ->
               err[:action] == :required_fields or
                 (is_map(err[:errors]) and err[:errors][:action] == :required_fields)
             end)
    end

    test "missing :body (cascaded enforce) → required error" do
      assert {:error, _} =
               CrossField.StrictEvent.builder(%{
                 source: "api",
                 payload: %{kind: "create"}
               })
    end

    test "missing :retries is FINE — `default:` opts it out of the cascade" do
      assert {:ok, ev} =
               CrossField.StrictEvent.builder(%{
                 source: "api",
                 payload: %{kind: "create", body: %{}}
               })

      assert ev.payload.retries == 0
    end

    test "missing :trace_id is FINE — `enforce: false` opts it out explicitly" do
      assert {:ok, _} =
               CrossField.StrictEvent.builder(%{
                 source: "api",
                 payload: %{kind: "create", body: %{}}
               })
    end

    test "missing :payload (the parent sub_field itself) → required error" do
      assert {:error, _} = CrossField.StrictEvent.builder(%{source: "api"})
    end

    test "inner submodule reports the cascade in its own enforce_keys/0" do
      keys = CrossField.StrictEvent.Payload.enforce_keys()
      assert :kind in keys
      assert :body in keys
      refute :retries in keys
      refute :trace_id in keys
    end
  end
end
