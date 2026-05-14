defmodule GuardedStructTest.VerifyNoStructCyclesTest do
  use ExUnit.Case, async: true

  alias GuardedStruct.Verifiers.VerifyNoStructCycles
  alias GuardedStruct.Dsl.{Field, SubField}

  defmodule InnerOK do
    use GuardedStruct

    guardedstruct do
      field :name, String.t()
    end
  end

  defmodule OuterOK do
    use GuardedStruct

    guardedstruct do
      field :name, String.t()
      field :inner, struct(), struct: InnerOK
    end
  end

  defp dsl_state(module, entities) do
    Spark.Dsl.Transformer.persist(
      %{[:guardedstruct] => %{entities: entities, opts: []}},
      :module,
      module
    )
  end

  defp self_ref_state(module) do
    dsl_state(module, [
      %Field{name: :name, type: nil},
      %Field{name: :child, type: nil, struct: module}
    ])
  end

  test "self-referential struct: raises with the cycle message" do
    state = self_ref_state(InnerOK)

    assert_raise Spark.Error.DslError, ~r/module reference cycle detected/, fn ->
      VerifyNoStructCycles.verify(state)
    end
  end

  test "self-referential structs: (list-of) also raises" do
    state =
      dsl_state(InnerOK, [
        %Field{name: :children, type: nil, structs: InnerOK}
      ])

    assert_raise Spark.Error.DslError, ~r/cycle/, fn ->
      VerifyNoStructCycles.verify(state)
    end
  end

  test "non-cyclic chain passes" do
    state =
      dsl_state(OuterOK, [
        %Field{name: :name, type: nil},
        %Field{name: :inner, type: nil, struct: InnerOK}
      ])

    assert :ok = VerifyNoStructCycles.verify(state)
  end

  test "module without struct/structs option passes" do
    state =
      dsl_state(InnerOK, [
        %Field{name: :name, type: nil}
      ])

    assert :ok = VerifyNoStructCycles.verify(state)
  end

  test "struct: pointing at a non-loaded module is silently allowed" do
    state =
      dsl_state(InnerOK, [
        %Field{name: :foo, type: nil, struct: NotAGuardedStructModule.Made.Up}
      ])

    assert :ok = VerifyNoStructCycles.verify(state)
  end

  test "recursing into a sub_field still walks struct: refs" do
    state =
      dsl_state(InnerOK, [
        %SubField{
          name: :auth,
          type: nil,
          fields: [
            %Field{name: :back, type: nil, struct: InnerOK}
          ],
          sub_fields: [],
          conditional_fields: []
        }
      ])

    assert_raise Spark.Error.DslError, ~r/cycle/, fn ->
      VerifyNoStructCycles.verify(state)
    end
  end
end
