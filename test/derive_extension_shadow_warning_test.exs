defmodule GuardedStructTest.DeriveExtensionShadowWarningTest do
  @moduledoc """
  Tests the compile-time shadow warning emitted by the
  `GuardedStruct.Derive.Extension.Transformers.Codegen` transformer.

  When a user declares a custom op (inside `derives do ... end`) whose
  name collides with a built-in (registered in
  `GuardedStruct.Derive.Registry`), the built-in's pattern-matched
  function clause in `ValidationDerive` / `SanitizerDerive` matches
  first — so the custom version would be dead code. We warn at compile
  time via `IO.warn/2`.
  """

  # async: false — `capture_io(:stderr, ...)` is process-global.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  defp compile_capture(code) do
    capture_io(:stderr, fn -> Code.eval_string(code) end)
  end

  describe "validator shadow warning" do
    test "warns when a validator shadows a built-in (e.g. :string)" do
      output =
        compile_capture("""
        defmodule ShadowsString do
          use GuardedStruct.Derive.Extension
          derives do
            validator :string, fn _ -> true end
          end
        end
        """)

      assert output =~ "validator"
      assert output =~ ":string"
      assert output =~ "shadows a built-in"
      assert output =~ "NEVER be called"
      assert output =~ "Rename it"
    end

    test "warns when validator shadows :integer, :email_r, :uuid, etc." do
      for name <- [:integer, :email_r, :uuid, :url, :max_len, :not_empty] do
        output =
          compile_capture("""
          defmodule Shadows#{Macro.camelize(to_string(name))} do
            use GuardedStruct.Derive.Extension
            derives do
              validator #{inspect(name)}, fn _ -> true end
            end
          end
          """)

        assert output =~ "shadows a built-in",
               "expected warning for validator #{inspect(name)}, got: #{inspect(output)}"

        assert output =~ inspect(name)
      end
    end

    test "warning includes the user module name for grep-ability" do
      output =
        compile_capture("""
        defmodule MyAppShadowsString do
          use GuardedStruct.Derive.Extension
          derives do
            validator :string, fn _ -> true end
          end
        end
        """)

      assert output =~ "MyAppShadowsString"
    end

    test "DOES NOT warn for non-shadowing names" do
      output =
        compile_capture("""
        defmodule NoShadowingValidator do
          use GuardedStruct.Derive.Extension
          derives do
            validator :my_custom_op, fn _ -> true end
          end
        end
        """)

      refute output =~ "shadows a built-in"
    end
  end

  describe "sanitizer shadow warning" do
    test "warns when a sanitizer shadows a built-in (e.g. :trim)" do
      output =
        compile_capture("""
        defmodule ShadowsTrim do
          use GuardedStruct.Derive.Extension
          derives do
            sanitizer :trim, fn input -> input end
          end
        end
        """)

      assert output =~ "sanitizer"
      assert output =~ ":trim"
      assert output =~ "shadows a built-in"
    end

    test "warns for each built-in sanitizer name shadowed" do
      for name <- [:downcase, :upcase, :capitalize, :strip_tags, :basic_html] do
        output =
          compile_capture("""
          defmodule ShadowsSanitize#{Macro.camelize(to_string(name))} do
            use GuardedStruct.Derive.Extension
            derives do
              sanitizer #{inspect(name)}, fn input -> input end
            end
          end
          """)

        assert output =~ "shadows a built-in",
               "expected warning for sanitizer #{inspect(name)}"
      end
    end

    test "DOES NOT warn for non-shadowing names" do
      output =
        compile_capture("""
        defmodule NoShadowingSanitizer do
          use GuardedStruct.Derive.Extension
          derives do
            sanitizer :my_slugify, fn input -> input end
          end
        end
        """)

      refute output =~ "shadows a built-in"
    end
  end

  describe "mixed shadowing in one extension module" do
    test "emits ONE warning per shadow, none for clean names" do
      output =
        compile_capture("""
        defmodule MixedShadowingExt do
          use GuardedStruct.Derive.Extension
          derives do
            validator :string, fn _ -> true end          # shadow
            validator :my_custom, fn _ -> true end       # clean
            sanitizer :trim, fn input -> input end       # shadow
            sanitizer :my_clean_op, fn input -> input end # clean
          end
        end
        """)

      # Two warnings — one per shadow
      shadow_count =
        output
        |> String.split("shadows a built-in")
        |> length()
        |> Kernel.-(1)

      assert shadow_count == 2

      # Both shadowed names mentioned, clean names not:
      assert output =~ ":string"
      assert output =~ ":trim"
      refute output =~ ":my_custom"
      refute output =~ ":my_clean_op"
    end
  end

  describe "shadow validator is actually dead code at runtime" do
    test "built-in :string wins; the custom one is never called" do
      output =
        capture_io(:stderr, fn ->
          Code.eval_string("""
          defmodule DeadCodeExt do
            use GuardedStruct.Derive.Extension
            derives do
              validator :string, fn _input -> true end
            end
          end

          defmodule UsesDeadCodeExt do
            use GuardedStruct, derive_extensions: [DeadCodeExt]
            guardedstruct do
              field :name, String.t(), derives: "validate(string)"
            end
          end
          """)
        end)

      # Confirm the warning fired (proof we're testing the right path):
      assert output =~ "shadows a built-in"

      # If the custom validator were live, `123` (an integer) would pass
      # because the custom fn always returns true. It DOESN'T pass because
      # the built-in :string clause matches first and rejects non-binaries.
      mod = :"Elixir.UsesDeadCodeExt"
      assert {:error, _} = apply(mod, :builder, [%{name: 123}])
      assert {:ok, _} = apply(mod, :builder, [%{name: "real string"}])
    end
  end
end
