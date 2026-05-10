defmodule GuardedStructTest.DerivesDeprecationTest do
  # async: false — we capture compile-time warnings via ExUnit.CaptureIO,
  # which is process-global.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  # Dynamic-eval helper. Returns {stderr_output, last_value_of_evaled_code}.
  # Wrapping the assertion-targeted module references in `apply/3` keeps the
  # compiler from emitting "module is undefined" warnings at static-analysis
  # time, since `Code.eval_string` defines them only at runtime.
  defp eval_with_stderr(code) do
    {output, result} =
      with_io_capture(fn -> Code.eval_string(code) end)

    {output, result}
  end

  defp with_io_capture(fun) do
    parent = self()
    ref = make_ref()

    output =
      capture_io(:stderr, fn ->
        send(parent, {ref, fun.()})
      end)

    receive do
      {^ref, val} -> {output, val}
    after
      0 -> {output, nil}
    end
  end

  test "derives: works as the canonical name" do
    defmodule CanonicalName do
      use GuardedStruct

      guardedstruct do
        field(:name, String.t(), derives: "validate(string, max_len=10)")
      end
    end

    assert {:ok, %{name: "ok"}} = CanonicalName.builder(%{name: "ok"})

    {:error, errs} = CanonicalName.builder(%{name: "this is way too long"})
    assert Enum.any?(errs, &(&1[:action] == :max_len))
  end

  test "legacy derive: still works but emits a deprecation warning at compile time" do
    {output, _} =
      eval_with_stderr("""
      defmodule LegacyDeriveStillWorks do
        use GuardedStruct

        guardedstruct do
          field(:name, String.t(), derive: "validate(string, max_len=10)")
        end
      end
      """)

    assert output =~ "deprecated"
    assert output =~ "derive:"
    assert output =~ "Use `derives:`"

    # `apply/3` with an atom avoids the static-analysis "undefined module" warning.
    mod = :"Elixir.LegacyDeriveStillWorks"
    assert {:ok, %{name: "ok"}} = apply(mod, :builder, [%{name: "ok"}])

    {:error, errs} = apply(mod, :builder, [%{name: "this is way too long"}])
    assert Enum.any?(errs, &(&1[:action] == :max_len))
  end

  test "when both derives: and derive: are set, derives: wins (no warning emitted)" do
    {output, _} =
      eval_with_stderr("""
      defmodule BothSet do
        use GuardedStruct

        guardedstruct do
          field(:name, String.t(),
            derives: "validate(string, max_len=100)",
            derive: "validate(string, max_len=5)"
          )
        end
      end
      """)

    # derives: wins, so the legacy derive: is never read — no warning.
    refute output =~ "deprecated"

    # derives: wins → 100-char limit applies, not the 5-char one.
    mod = :"Elixir.BothSet"
    assert {:ok, _} = apply(mod, :builder, [%{name: "longer than five chars"}])
  end

  test "deprecation warning mentions the field name and module" do
    {output, _} =
      eval_with_stderr("""
      defmodule DeprecationLocation do
        use GuardedStruct

        guardedstruct do
          field(:my_specific_field, String.t(), derive: "validate(string)")
        end
      end
      """)

    assert output =~ "my_specific_field"
    assert output =~ "DeprecationLocation"
  end
end
