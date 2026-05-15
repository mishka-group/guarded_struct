defmodule GuardedStructTest.Property.AshAtomicTest do
  @moduledoc """
  Properties of `GuardedStruct.AshResource.Change.atomic/3`.

  Inputs are generated with `Ash.Generator.action_input/3` so we get
  realistic, action-shaped attribute maps without hand-writing each
  fixture invocation.
  """

  use ExUnit.Case, async: false
  use ExUnitProperties

  @moduletag capture_log: true

  alias GuardedStruct.AshResource.Change
  alias GuardedStructTest.AshResources.{AtomicEligibleUser, AtomicWithCounter}

  describe "plain literals — atomic path" do
    property "for any random valid create input, atomic/3 returns {:atomic, sanitized_map}" do
      check all(input <- Ash.Generator.action_input(AtomicEligibleUser, :create)) do
        changeset = Ash.Changeset.for_create(AtomicEligibleUser, :create, input)

        case Change.atomic(changeset, [], %{}) do
          {:atomic, atomic_map} ->
            assert is_map(atomic_map)

            for {key, value} <- atomic_map do
              assert key in [:email, :username, :age, :role, :tenant_id, :country_code, :status]
              refute is_nil(value)
            end

          :ok ->
            assert input == %{} or Enum.empty?(Map.from_struct(changeset).attributes || %{})

          {:ok, _cs} ->
            :ok
        end
      end
    end

    property "the sanitized map agrees with __guarded_change__/1 for every owned field" do
      check all(input <- Ash.Generator.action_input(AtomicEligibleUser, :create)) do
        changeset = Ash.Changeset.for_create(AtomicEligibleUser, :create, input)

        case Change.atomic(changeset, [], %{}) do
          {:atomic, atomic_map} ->
            attrs = changeset.attributes || %{}

            case AtomicEligibleUser.__guarded_change__(attrs) do
              {:ok, expected} ->
                for {k, v} <- atomic_map do
                  assert Map.get(expected, k) == v
                end

              {:error, _} ->
                :ok
            end

          _ ->
            :ok
        end
      end
    end
  end

  describe "Ash.Expr in atomics" do
    property "an Ash.Expr value on an OWNED key bails to :not_atomic" do
      require Ash.Expr

      owned_keys = [:email, :username, :age, :role, :status]

      check all(field <- StreamData.member_of(owned_keys)) do
        cs =
          AtomicEligibleUser
          |> Ash.Changeset.for_create(:create, %{
            email: "x@y.io",
            username: "abc",
            age: 10,
            role: "user",
            tenant_id: "11111111-2222-3333-4444-555555555555",
            country_code: "us",
            status: "active"
          })
          |> Map.put(:attributes, %{})
          |> Map.put(:atomics, [{field, Ash.Expr.expr(fragment("?", "literal"))}])

        assert {:not_atomic, reason} = Change.atomic(cs, [], %{})
        assert reason =~ to_string(field)
      end
    end

    property "an Ash.Expr value on a NON-owned key passes through (no bail)" do
      require Ash.Expr

      check all(_ <- StreamData.integer(1..3)) do
        cs =
          AtomicWithCounter
          |> Ash.Changeset.for_create(:create, %{email: "x@y.io"})
          |> Map.put(:attributes, %{})
          |> Map.put(:atomics, last_seen_at: Ash.Expr.expr(now()))

        case Change.atomic(cs, [], %{}) do
          :ok -> :ok
          {:atomic, _} -> :ok
          other -> flunk("expected :ok or {:atomic, _}, got: #{inspect(other)}")
        end
      end
    end
  end

  describe "owned-field name set is stable" do
    property "every key in __guarded_field_name_set__/0 has a meta entry" do
      names = AtomicEligibleUser.__guarded_field_name_set__() |> MapSet.to_list()

      check all(name <- StreamData.member_of(names)) do
        assert is_map(AtomicEligibleUser.__guarded_field_meta__(name))
      end
    end
  end
end
