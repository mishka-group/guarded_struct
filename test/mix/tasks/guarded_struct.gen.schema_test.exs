defmodule Mix.Tasks.GuardedStruct.Gen.SchemaTest do
  use ExUnit.Case, async: true
  import Igniter.Test

  defmodule Fixture do
    use GuardedStruct

    guardedstruct do
      field(:name, String.t(), enforce: true, derives: "validate(string, max_len=80)")
      field(:age, integer(), derives: "validate(integer, min_len=0)")
      field(:role, String.t(), derives: "validate(enum=String[admin::user])")
    end
  end

  @fixture_name "Mix.Tasks.GuardedStruct.Gen.SchemaTest.Fixture"

  test "creates a JSON file at the path given by --out" do
    test_project()
    |> Igniter.compose_task("guarded_struct.gen.schema", [
      @fixture_name,
      "--out=priv/schemas/fixture.json"
    ])
    |> assert_creates("priv/schemas/fixture.json")
  end

  test "JSON output contains the field properties and required list" do
    igniter =
      test_project()
      |> Igniter.compose_task("guarded_struct.gen.schema", [
        @fixture_name,
        "--out=priv/schemas/fixture.json"
      ])

    source = igniter.rewrite.sources["priv/schemas/fixture.json"]
    assert source

    content = Rewrite.Source.get(source, :content)
    assert content =~ "\"properties\""
    assert content =~ "\"name\""
    assert content =~ "\"required\""
    assert content =~ "\"maxLength\""
  end

  test "TypeScript format emits an interface" do
    igniter =
      test_project()
      |> Igniter.compose_task("guarded_struct.gen.schema", [
        @fixture_name,
        "--format=typescript",
        "--out=priv/schemas/fixture.ts"
      ])

    source = igniter.rewrite.sources["priv/schemas/fixture.ts"]
    assert source

    content = Rewrite.Source.get(source, :content)
    assert content =~ "export interface"
    assert content =~ "name: string;"
    assert content =~ ~s(role?: "admin" | "user";)
  end

  test "without --out, the rendered schema is added as a notice" do
    igniter =
      test_project()
      |> Igniter.compose_task("guarded_struct.gen.schema", [@fixture_name])

    assert Enum.any?(igniter.notices, &(&1 =~ "Rendered schema"))
    refute Map.has_key?(igniter.rewrite.sources, "priv/schemas/")
  end

  test "unknown module produces an issue" do
    igniter =
      test_project()
      |> Igniter.compose_task("guarded_struct.gen.schema", [
        "Definitely.Not.A.Module"
      ])

    assert Enum.any?(igniter.issues, &(&1 =~ "not loaded"))
  end

  test "non-GuardedStruct module produces an issue" do
    igniter =
      test_project()
      |> Igniter.compose_task("guarded_struct.gen.schema", ["String"])

    assert Enum.any?(igniter.issues, &(&1 =~ "doesn't appear to be a GuardedStruct"))
  end

  test "unknown format produces an issue" do
    igniter =
      test_project()
      |> Igniter.compose_task("guarded_struct.gen.schema", [
        @fixture_name,
        "--format=xml"
      ])

    assert Enum.any?(igniter.issues, &(&1 =~ "Unknown format"))
  end
end
