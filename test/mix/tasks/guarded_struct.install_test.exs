defmodule Mix.Tasks.GuardedStruct.InstallTest do
  use ExUnit.Case, async: false
  import Igniter.Test

  # Igniter's compose_task path evaluates the test-project's virtual
  # config.exs against the host process's Application env. We snapshot
  # and restore to keep the suite hermetic.
  setup do
    snapshot = Application.get_all_env(:guarded_struct)

    on_exit(fn ->
      Application.get_all_env(:guarded_struct)
      |> Enum.each(fn {k, _} -> Application.delete_env(:guarded_struct, k) end)

      Enum.each(snapshot, fn {k, v} -> Application.put_env(:guarded_struct, k, v) end)
    end)

    :ok
  end

  test "installs the lint alias" do
    igniter =
      test_project()
      |> Igniter.compose_task("guarded_struct.install", [])

    mix_exs = igniter.rewrite.sources["mix.exs"]
    content = Rewrite.Source.get(mix_exs, :content)

    assert content =~ "lint:"
    assert content =~ "spark.formatter"
    assert content =~ "format"
  end

  test "seeds derive_extensions: [] in config.exs" do
    igniter =
      test_project()
      |> Igniter.compose_task("guarded_struct.install", [])

    config = igniter.rewrite.sources["config/config.exs"]
    assert config

    content = Rewrite.Source.get(config, :content)
    assert content =~ ":guarded_struct"
    assert content =~ "derive_extensions"
  end

  test "emits a quick-start notice" do
    igniter =
      test_project()
      |> Igniter.compose_task("guarded_struct.install", [])

    assert Enum.any?(igniter.notices, &(&1 =~ "guarded_struct installed"))
    assert Enum.any?(igniter.notices, &(&1 =~ "guardedstruct do"))
  end
end
