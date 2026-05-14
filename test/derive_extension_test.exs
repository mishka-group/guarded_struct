defmodule GuardedStructTest.DeriveExtensionTest do
  use ExUnit.Case, async: false

  alias GuardedStructTest.Fixtures.DeriveExtension.{SlugDerives, WithSlug, WithSlugify}

  setup do
    Application.put_env(:guarded_struct, :derive_extensions, [SlugDerives])
    on_exit(fn -> Application.delete_env(:guarded_struct, :derive_extensions) end)
    :ok
  end

  test "registered extension exposes its validator/sanitizer names" do
    assert SlugDerives.__validators__() == [:slug]
    assert SlugDerives.__sanitizers__() == [:slugify]
    assert SlugDerives.__derive_extension__?()
  end

  test "extension validator runs against input" do
    assert {:ok, %{slug: "valid-slug"}} = WithSlug.builder(%{slug: "valid-slug"})

    assert {:error, [%{field: :slug, action: :slug}]} =
             WithSlug.builder(%{slug: "Not Valid Slug!"})
  end

  test "extension sanitizer runs against input" do
    assert {:ok, %{slug: "hello-world"}} = WithSlugify.builder(%{slug: "Hello World!"})
  end

  test "extension dispatch finds the registered op" do
    assert "abc" = GuardedStruct.Derive.Extension.dispatch_validate(:slug, "abc", :test)

    assert {:error, :test, :slug, _} =
             GuardedStruct.Derive.Extension.dispatch_validate(:slug, "AB!", :test)

    assert :__not_found__ =
             GuardedStruct.Derive.Extension.dispatch_validate(:nonexistent, "x", :test)
  end

  test "all_extension_validators aggregates across registered modules" do
    assert :slug in MapSet.to_list(GuardedStruct.Derive.Extension.all_extension_validators())
  end
end
