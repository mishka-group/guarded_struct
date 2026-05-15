defmodule GuardedStructTest.Property.BuilderInvariantsTest do
  @moduledoc """
  Invariants that must hold across `builder/1` and the generated
  introspection surface for any guarded module.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GuardedStructTest.PropertyFixtures.{Account, RequiredOnly, Tagged}

  describe "builder/1 return shape" do
    property "always returns {:ok, struct} or {:error, list} on map inputs" do
      check all(attrs <- random_attrs_for_account()) do
        case Account.builder(attrs) do
          {:ok, %Account{}} -> :ok
          {:error, errs} when is_list(errs) -> :ok
          other -> flunk("unexpected return shape: #{inspect(other)}")
        end
      end
    end
  end

  describe "valid-input round-trip" do
    property "every well-formed input produces a struct whose declared fields equal the input" do
      check all(
              email_user <- StreamData.string(:alphanumeric, min_length: 1, max_length: 12),
              email_host <- StreamData.string(:alphanumeric, min_length: 1, max_length: 8),
              age <- StreamData.integer(0..150)
            ) do
        email = email_user <> "@" <> email_host <> ".io"

        assert {:ok, %Account{email: out_email, age: ^age}} =
                 Account.builder(%{email: email, age: age})

        assert out_email == String.downcase(email)
      end
    end
  end

  describe "required-fields enforcement" do
    property "any input missing at least one enforce-true key surfaces a :required_fields error" do
      keys = [:a, :b, :c]
      missing_gen = StreamData.nonempty(StreamData.list_of(StreamData.member_of(keys), max_length: 3))

      check all(raw <- missing_gen) do
        missing = Enum.uniq(raw)
        attrs = Map.new(keys -- missing, fn k -> {k, "x"} end)

        assert {:error, errs} = RequiredOnly.builder(attrs)

        flat_errors =
          errs
          |> List.wrap()
          |> Enum.flat_map(fn
            %{errors: inner} when is_list(inner) -> inner
            other -> [other]
          end)

        assert Enum.any?(flat_errors, &match?(%{action: :required_fields}, &1)),
               "expected a :required_fields error in #{inspect(errs)}, missing=#{inspect(missing)}, _missing_gen=#{inspect(missing_gen)}"
      end
    end

    property "complete input never produces required_fields errors" do
      check all(
              a <- StreamData.string(:alphanumeric, min_length: 1, max_length: 10),
              b <- StreamData.string(:alphanumeric, min_length: 1, max_length: 10),
              c <- StreamData.string(:alphanumeric, min_length: 1, max_length: 10)
            ) do
        assert {:ok, %RequiredOnly{}} = RequiredOnly.builder(%{a: a, b: b, c: c})
      end
    end
  end

  describe "introspection invariants" do
    property "for every fixture, enforce_keys ⊆ keys" do
      check all(module <- StreamData.member_of([Account, RequiredOnly, Tagged])) do
        assert Enum.all?(module.enforce_keys(), &(&1 in module.keys()))
      end
    end

    property "__field_meta__/1 returns a metadata map iff the field is in keys (Account)" do
      check all(name <- StreamData.atom(:alphanumeric)) do
        in_keys? = name in Account.keys()
        meta = Account.__field_meta__(name)

        cond do
          in_keys? -> assert is_map(meta), "expected meta for known field #{inspect(name)}"
          true -> assert is_nil(meta), "expected nil for unknown field #{inspect(name)}"
        end
      end
    end
  end

  describe "Tagged.builder/1 — dynamic_field identity" do
    property "metadata map is passed through verbatim regardless of key shape" do
      uuid_gen = StreamData.constant("11111111-2222-3333-4444-555555555555")

      key_gen =
        StreamData.one_of([
          StreamData.string(:alphanumeric, min_length: 1, max_length: 12),
          StreamData.atom(:alphanumeric)
        ])

      val_gen =
        StreamData.one_of([
          StreamData.integer(),
          StreamData.string(:alphanumeric, max_length: 20),
          StreamData.boolean()
        ])

      meta_gen =
        StreamData.map_of(key_gen, val_gen, max_length: 6)

      check all(
              id <- uuid_gen,
              meta <- meta_gen
            ) do
        assert {:ok, %Tagged{metadata: out}} = Tagged.builder(%{id: id, metadata: meta})
        assert out == meta
      end
    end
  end

  defp random_attrs_for_account do
    email_gen =
      StreamData.one_of([
        StreamData.string(:alphanumeric, max_length: 30),
        StreamData.constant("a@b.co"),
        StreamData.constant("")
      ])

    age_gen =
      StreamData.one_of([
        StreamData.integer(-10..200),
        StreamData.constant(nil),
        StreamData.constant("not-int")
      ])

    nickname_gen =
      StreamData.one_of([
        StreamData.string(:alphanumeric, max_length: 30),
        StreamData.constant(nil)
      ])

    StreamData.bind(
      StreamData.tuple({email_gen, age_gen, nickname_gen}),
      fn {email, age, nick} ->
        attrs = %{email: email, age: age, nickname: nick}
        StreamData.constant(attrs)
      end
    )
  end
end
