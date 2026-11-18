defmodule GuardedStructTest.TypedocTest do
  use ExUnit.Case, async: true

  alias GuardedStructTest.Fixtures.{TypedocOwnTypedoc, TypedocParent, TypedocPattern}

  @address "GuardedStructTest.Fixtures.TypedocAddress"
  @parent "GuardedStructTest.Fixtures.TypedocParent"

  defp typedoc(module) do
    {:docs_v1, _, :elixir, _, _, _, docs} = Code.fetch_docs(module)
    {_, _, _, doc, _} = Enum.find(docs, &match?({{:type, :t, 0}, _, _, _, _}, &1))
    doc
  end

  defp moduledoc(module) do
    {:docs_v1, _, :elixir, _, moduledoc, _, _} = Code.fetch_docs(module)
    moduledoc
  end

  # The one type `module` declares, as text.
  defp only_type(module) do
    {:ok, [{:type, spec}]} = Code.Typespec.fetch_types(module)
    Macro.to_string(Code.Typespec.type_to_quoted(spec))
  end

  defp compile(source), do: Code.compile_string(source)

  # The type of each field of `t()`, as text.
  defp field_types(module) do
    {:ok, types} = Code.Typespec.fetch_types(module)
    {_, {:t, _, []} = spec} = Enum.find(types, &match?({_, {:t, _, []}}, &1))
    {:"::", _, [_, {:%, _, [_, {:%{}, _, fields}]}]} = Code.Typespec.type_to_quoted(spec)

    Map.new(fields, fn {name, type} ->
      {name, type |> Macro.to_string() |> String.replace(~r/\s+/, " ")}
    end)
  end

  describe "the types in t()" do
    test "struct: and structs: give the module's t()" do
      types = field_types(TypedocParent)
      assert types.address == "#{@address}.t() | nil"
      assert types.addresses == "[#{@address}.t()] | nil"
    end

    test "a sub_field is the t() of its module, a list in list mode" do
      types = field_types(TypedocParent)
      assert types.profile == "#{@parent}.Profile.t() | nil"
      assert types.lines == "[#{@parent}.Lines.t()] | nil"
    end

    test "a conditional_field is the union of its branches" do
      assert field_types(TypedocParent).plan ==
               "(String.t() | #{@parent}.Plan1.t() | #{@address}.t()) | nil"
    end

    test "a declared type that already says something is kept" do
      types = field_types(TypedocParent)
      assert types.kept == "#{@address}.t() | nil"
      assert types.count == "integer() | nil"
      assert types.meta == "map() | nil"
    end

    test "an enforced field has no nil" do
      assert field_types(TypedocParent).name == "String.t()"
    end

    test "a pattern-keyed map has a t() too" do
      assert only_type(TypedocPattern) == "t() :: %{optional(String.t()) => String.t()}"
    end
  end

  describe "the @typedoc of t()" do
    test "is a table of the fields" do
      %{"en" => doc} = typedoc(TypedocParent)

      assert doc =~ "The struct that `builder/1` returns."
      assert doc =~ "| Field | Type | Required | Default | Description | Derives |"

      assert doc =~
               "| `:name` | `String.t()` | yes |  | The name; a \\| pipe stays in its cell. | " <>
                 "`sanitize(trim) validate(string)` |"

      assert doc =~
               "| `:address` | [`#{@address}.t()`](`t:#{@address}.t/0`) \\| `nil` | no |  | " <>
                 "Where the parent lives. |  |"

      assert doc =~
               "| `:lines` | [`[#{@parent}.Lines.t()]`](`t:#{@parent}.Lines.t/0`) \\| `nil` | no |"

      assert doc =~
               "| `:count` | `integer()` \\| `nil` | no | `0` |  | validator `{#{@parent}, :check}` |"

      assert doc =~
               "| `:meta` | `map()` \\| `nil` | no | `%{}` | Free-form data. | `validate(map)` |"
    end

    test "a sub_field's row takes the first paragraph of its doc:" do
      %{"en" => doc} = typedoc(TypedocParent)
      assert doc =~ "| The profile of the parent. |  |"
      refute doc =~ "A second paragraph"
    end

    test "a conditional_field links each branch that is a struct" do
      %{"en" => doc} = typedoc(TypedocParent)

      assert doc =~
               "| `:plan` | `String.t()` \\| [`#{@parent}.Plan1.t()`](`t:#{@parent}.Plan1.t/0`) " <>
                 "\\| [`#{@address}.t()`](`t:#{@address}.t/0`) \\| `nil` | no |  | " <>
                 "A plan by name or in detail. |  |"
    end

    test "a sub_field with doc: false keeps its declared type, as its module has no page" do
      %{"en" => doc} = typedoc(TypedocParent)
      assert doc =~ "| `:internal` | `struct()` \\| `nil` | no |"
      assert field_types(TypedocParent).internal == "struct() | nil"
    end

    test "a field with doc: false is left out of the table" do
      %{"en" => doc} = typedoc(TypedocParent)
      refute doc =~ ":secret"
      assert Map.has_key?(field_types(TypedocParent), :secret)
    end

    test "virtual fields are listed apart" do
      %{"en" => doc} = typedoc(TypedocParent)
      [_fields, virtual] = String.split(doc, "Virtual fields:")

      assert virtual =~
               "| `:confirm` | `String.t()` \\| `nil` | no |  | Checked, then dropped. |  |"
    end

    test "a generated sub_field module gets its own table" do
      %{"en" => doc} = typedoc(TypedocParent.Profile)
      assert doc =~ "| `:bio` | `String.t()` \\| `nil` | no |  | A short bio. |  |"
    end

    test "a pattern-keyed map lists its key patterns" do
      %{"en" => doc} = typedoc(TypedocPattern)
      assert doc =~ "| Key pattern |"
      assert doc =~ "| `~r/^env_/` | `String.t()` | no |  | An environment value. |  |"
    end

    test "the user's own @typedoc wins" do
      assert typedoc(TypedocOwnTypedoc) == %{"en" => "My own words about t."}
    end

    test "the @moduledoc stays as written" do
      assert moduledoc(TypedocParent) == %{"en" => "The parent's own doc."}
    end
  end

  describe "the doc: option" do
    for {entity, line} <- [
          field: "field :id, String.t(), doc: 12",
          virtual_field: "virtual_field :id, String.t(), doc: :text",
          dynamic_field: "dynamic_field :meta, doc: true",
          conditional_field: """
          conditional_field :id, any(), doc: [1] do
            field :id, String.t()
          end
          """
        ] do
      test "Spark refuses a doc: on #{entity} that is not a string or false" do
        source = """
        defmodule GuardedStructTest.TypedocTest.BadDoc#{unquote(entity) |> Atom.to_string() |> Macro.camelize()} do
          use GuardedStruct

          guardedstruct do
            #{unquote(line)}
          end
        end
        """

        assert_raise Spark.Error.DslError, ~r/doc/, fn -> compile(source) end
      end
    end
  end
end
