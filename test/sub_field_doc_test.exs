defmodule GuardedStructTest.SubFieldDocTest do
  use ExUnit.Case, async: true

  alias GuardedStructTest.Fixtures.SubFieldDoc

  defp moduledoc(module) do
    {:docs_v1, _anno, :elixir, _format, moduledoc, _meta, _docs} = Code.fetch_docs(module)
    moduledoc
  end

  test "the doc: option is the @moduledoc of the module a sub_field generates" do
    assert moduledoc(SubFieldDoc.Transaction) == %{
             "en" => "One movement of the seller's balance.\n"
           }
  end

  test "a sub_field inside a sub_field takes its own doc:" do
    assert moduledoc(SubFieldDoc.Transaction.Fee) == %{
             "en" => "The fee taken from one transaction."
           }
  end

  test "a list sub_field (structs: true) takes doc:" do
    assert moduledoc(SubFieldDoc.Lines) == %{"en" => "One line of the order."}
  end

  test "the doc setter inside the sub_field block works like the option" do
    assert moduledoc(SubFieldDoc.Setter) == %{
             "en" => "Set with the setter form inside the block."
           }
  end

  test "a conditional_field's sub_field takes doc: on its numbered module" do
    assert moduledoc(SubFieldDoc.Plan1) == %{"en" => "A plan given in detail."}
  end

  test "doc: false hides the module from the docs" do
    assert moduledoc(SubFieldDoc.Internal) == :hidden
  end

  test "without doc: the module has no @moduledoc, as before" do
    assert moduledoc(SubFieldDoc.Plain) == :none
  end

  test "doc: does not change what the module builds" do
    assert {:ok, %SubFieldDoc.Transaction{id: "t1", fee: %SubFieldDoc.Transaction.Fee{amount: 5}}} =
             SubFieldDoc.Transaction.builder(%{id: "t1", fee: %{amount: 5}})
  end

  test "the parent's own @moduledoc stays exactly as written" do
    assert moduledoc(GuardedStructTest.Fixtures.SubFieldDocParent) == %{
             "en" => "The parent's own doc."
           }

    assert moduledoc(GuardedStructTest.Fixtures.SubFieldDocParent.Child) == %{
             "en" => "The child's **own** doc."
           }
  end

  test "a parent without @moduledoc gets no doc text" do
    # Spark sets an empty @moduledoc on a DSL module that has none; no text is added.
    assert moduledoc(GuardedStructTest.Fixtures.SubFieldDocNoParentDoc) in [:none, %{"en" => ""}]
  end

  test "a parent with @moduledoc false stays hidden" do
    assert moduledoc(SubFieldDoc) == :hidden
  end

  test "doc: and the doc setter in the same sub_field are refused" do
    source = """
    defmodule GuardedStructTest.SubFieldDocTest.BothDocs do
      use GuardedStruct

      guardedstruct do
        sub_field :profile, struct(), doc: "B" do
          doc "C"
          field :id, String.t()
        end
      end
    end
    """

    assert_raise Spark.Error.DslError, ~r/Multiple values for key `:doc`/, fn ->
      Code.compile_string(source)
    end
  end

  test "a doc: that is not a string or false is refused when the module compiles" do
    source = """
    defmodule GuardedStructTest.SubFieldDocTest.BadDoc do
      use GuardedStruct

      guardedstruct do
        sub_field :profile, struct(), doc: 123 do
          field :id, String.t()
        end
      end
    end
    """

    assert_raise Spark.Error.DslError, ~r/expected :doc option/, fn ->
      Code.compile_string(source)
    end
  end
end
