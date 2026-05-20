defmodule GuardedStructTest.DeriveExtensionTest do
  use ExUnit.Case, async: false

  alias GuardedStructTest.Fixtures.DeriveExtension.{SlugDerives, WithSlug, WithSlugify}

  setup do
    Application.put_env(:guarded_struct, :derive_extensions, [SlugDerives])
    on_exit(fn -> Application.delete_env(:guarded_struct, :derive_extensions) end)
    :ok
  end

  test "registered extension exposes its validator/sanitizer names" do
    assert SlugDerives.__validators__() == [:my_slug]
    assert SlugDerives.__sanitizers__() == [:slugify]
    assert SlugDerives.__derive_extension__?()
  end

  test "extension validator runs against input" do
    assert {:ok, %{my_slug: "valid-slug"}} = WithSlug.builder(%{my_slug: "valid-slug"})

    assert {:error, [%{field: :my_slug, action: :my_slug}]} =
             WithSlug.builder(%{my_slug: "Not Valid Slug!"})
  end

  test "extension sanitizer runs against input" do
    assert {:ok, %{my_slug: "hello-world"}} = WithSlugify.builder(%{my_slug: "Hello World!"})
  end

  test "extension dispatch finds the registered op" do
    assert "abc" = GuardedStruct.Derive.Extension.dispatch_validate(:my_slug, "abc", :test)

    assert {:error, :test, :my_slug, _} =
             GuardedStruct.Derive.Extension.dispatch_validate(:my_slug, "AB!", :test)

    assert :__not_found__ =
             GuardedStruct.Derive.Extension.dispatch_validate(:nonexistent, "x", :test)
  end

  test "all_extension_validators aggregates across registered modules" do
    assert :my_slug in MapSet.to_list(GuardedStruct.Derive.Extension.all_extension_validators())
  end
end
