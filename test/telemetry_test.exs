defmodule GuardedStructTest.TelemetryTest do
  use ExUnit.Case, async: false

  defmodule Sample do
    use GuardedStruct

    guardedstruct do
      field(:name, String.t(), enforce: true, derives: "validate(string, max_len=80)")
      field(:age, integer(), derives: "validate(integer, min_len=0)")
    end
  end

  def __telemetry_forward__(event, measurements, metadata, %{pid: pid}) do
    send(pid, {:telemetry, event, measurements, metadata})
  end

  setup do
    handler_id = "test-handler-#{:erlang.unique_integer([:positive])}"
    test_pid = self()

    :telemetry.attach_many(
      handler_id,
      [
        [:guarded_struct, :builder, :start],
        [:guarded_struct, :builder, :stop],
        [:guarded_struct, :builder, :exception]
      ],
      &__MODULE__.__telemetry_forward__/4,
      %{pid: test_pid}
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    {:ok, handler_id: handler_id}
  end

  test "emits :start before the build runs" do
    Sample.builder(%{name: "Alice"})

    assert_receive {:telemetry, [:guarded_struct, :builder, :start], measurements, metadata}
    assert is_integer(measurements.system_time)
    assert metadata.module == Sample
  end

  test "emits :stop with duration and result on success" do
    Sample.builder(%{name: "Alice", age: 30})

    assert_receive {:telemetry, [:guarded_struct, :builder, :stop], measurements, metadata}
    assert is_integer(measurements.duration)
    assert measurements.duration >= 0
    assert metadata.module == Sample
    assert metadata.result == :ok
  end

  test "emits :stop with error_count on validation failure" do
    Sample.builder(%{age: -5})

    assert_receive {:telemetry, [:guarded_struct, :builder, :stop], _, metadata}
    assert metadata.result == :error
    assert is_integer(metadata.error_count)
    assert metadata.error_count >= 1
  end

  test "emits :exception when builder raises" do
    defmodule WithBoom do
      use GuardedStruct

      guardedstruct error: true do
        field(:name, String.t(), enforce: true)
      end
    end

    assert_raise WithBoom.Error, fn ->
      WithBoom.builder(%{}, true)
    end

    # build/3 raises through, but the exception event should fire on the
    # FAILED-BUILD path (when error?: true → handle_error raises)
    assert_received {:telemetry, [:guarded_struct, :builder, :start], _, _}
  end

  test "nested sub_field builds do NOT emit (only top-level public entry)" do
    defmodule WithNested do
      use GuardedStruct

      guardedstruct do
        field(:name, String.t())

        sub_field(:auth, struct()) do
          field(:role, String.t())
        end
      end
    end

    WithNested.builder(%{name: "x", auth: %{role: "admin"}})

    # Drain all received telemetry messages and count :start events.
    starts =
      Stream.repeatedly(fn ->
        receive do
          {:telemetry, [:guarded_struct, :builder, :start], _, _} -> :start
          _ -> :other
        after
          50 -> :timeout
        end
      end)
      |> Enum.take_while(&(&1 != :timeout))
      |> Enum.count(&(&1 == :start))

    # Exactly one :start, even though sub_field(:auth) builds internally.
    assert starts == 1
  end
end
