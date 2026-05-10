defmodule Mix.Tasks.GuardedStruct.Gen.StructTest do
  use ExUnit.Case, async: true
  import Igniter.Test

  test "creates the module file at the expected path" do
    igniter =
      test_project()
      |> Igniter.compose_task("guarded_struct.gen.struct", [
        "MyApp.User",
        "name:string",
        "age:integer"
      ])

    source = igniter.rewrite.sources["lib/my_app/user.ex"]
    assert source

    content = Rewrite.Source.get(source, :content)
    assert content =~ "defmodule MyApp.User"
    assert content =~ "use GuardedStruct"
    assert content =~ "guardedstruct do"
  end

  test "renders fields with appropriate types and derives" do
    igniter =
      test_project()
      |> Igniter.compose_task("guarded_struct.gen.struct", [
        "MyApp.User",
        "name:string",
        "age:integer",
        "active:boolean",
        "uuid:uuid"
      ])

    content = igniter.rewrite.sources["lib/my_app/user.ex"] |> Rewrite.Source.get(:content)

    assert content =~ ~s|field(:name, String.t(), derives: "validate(string)")|
    assert content =~ ~s|field(:age, integer(), derives: "validate(integer)")|
    assert content =~ ~s|field(:active, boolean(), derives: "validate(boolean)")|
    assert content =~ ~s|field(:uuid, String.t(), derives: "validate(uuid)")|
  end

  test "name! marks the field as enforce: true" do
    igniter =
      test_project()
      |> Igniter.compose_task("guarded_struct.gen.struct", [
        "MyApp.Account",
        "id!:uuid",
        "name!:string",
        "bio:string"
      ])

    content = igniter.rewrite.sources["lib/my_app/account.ex"] |> Rewrite.Source.get(:content)

    assert content =~ "enforce: true"
    # 2 enforce fields, 1 not
    assert content |> String.split("enforce: true") |> length() == 3
  end

  test "unknown type falls back to any() with no derive" do
    igniter =
      test_project()
      |> Igniter.compose_task("guarded_struct.gen.struct", [
        "MyApp.Bag",
        "stuff:weird_type"
      ])

    content = igniter.rewrite.sources["lib/my_app/bag.ex"] |> Rewrite.Source.get(:content)

    assert content =~ "field(:stuff, any())"
    refute content =~ "derives:"
  end

  test "no fields → empty body" do
    igniter =
      test_project()
      |> Igniter.compose_task("guarded_struct.gen.struct", ["MyApp.Empty"])

    content = igniter.rewrite.sources["lib/my_app/empty.ex"] |> Rewrite.Source.get(:content)

    assert content =~ "guardedstruct do"
    refute content =~ "field("
  end
end
