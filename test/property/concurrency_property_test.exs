defmodule GuardedStructTest.Property.ConcurrencyTest do
  @moduledoc """
  Process-isolation and cleanup properties.

  GuardedStruct uses the process dictionary in two places — the Ash
  auto-map cascade (`:guarded_as_map?`) and the per-module derive
  extensions stack (`:guarded_struct_current_module`). These properties
  verify that parallel builds never leak state to each other and that
  `with_module_context` cleans up even when the inner pipeline raises.
  """

  use ExUnit.Case, async: false
  use ExUnitProperties

  alias GuardedStructTest.PropertyFixtures.{Account, Deeply}

  describe "parallel builders" do
    property "N concurrent builds match their sequential counterparts" do
      check all(
              inputs <-
                StreamData.list_of(account_input(), min_length: 8, max_length: 32),
              max_runs: 25
            ) do
        sequential = Enum.map(inputs, &Account.builder/1)

        parallel =
          inputs
          |> Task.async_stream(&Account.builder/1, max_concurrency: 16, ordered: true)
          |> Enum.map(fn {:ok, r} -> r end)

        assert parallel == sequential
      end
    end
  end

  describe "process-dict isolation" do
    property "the auto-map flag set by another process is invisible to this one" do
      check all(_ <- StreamData.integer(1..3)) do
        # In a separate process, force the as-map flag on.
        Task.await(
          Task.async(fn -> Process.put(:guarded_as_map?, true) end)
        )

        assert Process.get(:guarded_as_map?) == nil
      end
    end

    property "a top-level build never leaks pdict keys after returning" do
      check all(input <- account_input()) do
        Process.delete(:guarded_as_map?)
        Process.delete(:guarded_struct_current_module)

        _ = Account.builder(input)

        assert Process.get(:guarded_as_map?) == nil
        assert Process.get(:guarded_struct_current_module) == nil
      end
    end
  end

  describe "with_module_context cleanup under exceptions" do
    property "if the inner builder raises, the current-module pdict is restored" do
      check all(_ <- StreamData.integer(1..3)) do
        Process.delete(:guarded_struct_current_module)
        Process.put(:guarded_struct_current_module, :prior_sentinel)

        _ =
          try do
            Deeply.builder(%{l1: {:not_a_map}})
          rescue
            _ -> :ok
          catch
            _, _ -> :ok
          end

        assert Process.get(:guarded_struct_current_module) == :prior_sentinel
        Process.delete(:guarded_struct_current_module)
      end
    end
  end

  defp account_input do
    email_user = StreamData.string(:alphanumeric, min_length: 1, max_length: 8)
    email_host = StreamData.string(:alphanumeric, min_length: 1, max_length: 6)
    age_gen = StreamData.integer(0..120)

    StreamData.bind(
      StreamData.tuple({email_user, email_host, age_gen}),
      fn {u, h, age} ->
        StreamData.constant(%{
          email: "  #{u}@#{h}.io  ",
          age: age,
          nickname: "user_#{u}"
        })
      end
    )
  end
end
