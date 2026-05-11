defmodule GuardedStructFixtures.Records do
  @moduledoc """
  Erlang Records via `validate(record=Tag)`.

  Exercises:
    * `validate(record)` — any tagged-tuple shape
    * `validate(record=Tag)` — specific tag

  Real-world use: bridging Elixir code that wraps Erlang OTP returns
  (e.g. `:mnesia` rows, `:gen_event` notifications) into typed structs.
  """

  require Record
  Record.defrecord(:user, :user, name: nil, age: nil)
  Record.defrecord(:address, :address, street: nil, city: nil, zip: nil)

  defmodule UserEvent do
    use GuardedStruct

    guardedstruct do
      field(:event_kind, atom(),
        enforce: true,
        derives: "validate(enum=Atom[created::updated::deleted])"
      )

      field(:user, :tuple, enforce: true, derives: "validate(record=user)")
      field(:trace, :tuple, derives: "validate(record)")
    end
  end
end
