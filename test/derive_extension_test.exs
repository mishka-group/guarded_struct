defmodule GuardedStructTest.DeriveExtensionTest do
  use ExUnit.Case, async: false

  defmodule SlugDerives do
    use GuardedStruct.Derive.Extension

    validator(:slug, fn input ->
      is_binary(input) and Regex.match?(~r/^[a-z0-9-]+$/, input)
    end)

    sanitizer(:slugify, fn input when is_binary(input) ->
      input
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9-]+/u, "-")
      |> String.trim("-")
    end)
  end

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
    defmodule WithSlug do
      use GuardedStruct

      guardedstruct do
        field(:slug, String.t(), derives: "validate(slug)")
      end
    end

    assert {:ok, %{slug: "valid-slug"}} = WithSlug.builder(%{slug: "valid-slug"})

    assert {:error, [%{field: :slug, action: :slug}]} =
             WithSlug.builder(%{slug: "Not Valid Slug!"})
  end

  test "extension sanitizer runs against input" do
    defmodule WithSlugify do
      use GuardedStruct

      guardedstruct do
        field(:slug, String.t(), derives: "sanitize(slugify) validate(slug)")
      end
    end

    assert {:ok, %{slug: "hello-world"}} = WithSlugify.builder(%{slug: "Hello World!"})
  end

  test "extension dispatch finds the registered op" do
    assert "abc" =
             GuardedStruct.Derive.Extension.dispatch_validate(:slug, "abc", :test)

    assert {:error, :test, :slug, _} =
             GuardedStruct.Derive.Extension.dispatch_validate(:slug, "AB!", :test)

    assert :__not_found__ =
             GuardedStruct.Derive.Extension.dispatch_validate(:nonexistent, "x", :test)
  end

  test "all_extension_validators aggregates across registered modules" do
    assert :slug in MapSet.to_list(GuardedStruct.Derive.Extension.all_extension_validators())
  end

  test "extension ops pass strict op-name verification" do
    Application.put_env(:guarded_struct, :strict_derive_ops, true)
    on_exit(fn -> Application.delete_env(:guarded_struct, :strict_derive_ops) end)

    # Compile a module with strict mode on; the extension-registered :slug
    # op should NOT trigger the unknown-op error.
    [{mod, _}] =
      Code.compile_string("""
      defmodule StrictWithSlug do
        use GuardedStruct

        guardedstruct do
          field(:slug, String.t(), derives: "validate(slug)")
        end
      end
      """)

    assert mod == StrictWithSlug
    assert {:ok, _} = mod.builder(%{slug: "ok-slug"})
  end
end
