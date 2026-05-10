defmodule GuardedStructTest.VerifyCoreKeyPathsTest do
  # async: false — setup mutates Application env which is global across test
  # processes. Running async risks other test files compiling fixtures while
  # strict_core_key_paths is on, triggering false-positive path errors.
  use ExUnit.Case, async: false

  alias GuardedStruct.Transformers.VerifyCoreKeyPaths
  alias GuardedStruct.Dsl.{Field, SubField}

  # No setup — these tests call verify!/1 directly with synthetic state, so
  # the global :strict_core_key_paths env doesn't matter and we avoid the
  # parallel-process race that flipping it would otherwise cause.

  defp dsl_state(entities, module \\ FakeModule) do
    Spark.Dsl.Transformer.persist(
      %{[:guardedstruct] => %{entities: entities, opts: []}},
      :module,
      module
    )
  end

  defp field(name, opts \\ []) do
    %Field{
      name: name,
      type: nil,
      __from_path__: opts[:from_path],
      __on_path__: opts[:on_path]
    }
  end

  defp sub_field(name, children) do
    %SubField{
      name: name,
      type: nil,
      fields: Keyword.get(children, :fields, []),
      sub_fields: Keyword.get(children, :sub_fields, []),
      conditional_fields: []
    }
  end

  test "passes when from: path resolves to a sibling" do
    state =
      dsl_state([
        field(:source),
        field(:dest, from_path: [:source])
      ])

    assert {:ok, _} = VerifyCoreKeyPaths.verify!(state)
  end

  test "passes when from: root::path resolves to top-level field" do
    state =
      dsl_state([
        field(:source),
        field(:dest, from_path: [:root, :source])
      ])

    assert {:ok, _} = VerifyCoreKeyPaths.verify!(state)
  end

  test "raises when from: path target does not exist" do
    state =
      dsl_state([
        field(:dest, from_path: [:nonexistent])
      ])

    assert_raise Spark.Error.DslError, ~r/references `:nonexistent`/, fn ->
      VerifyCoreKeyPaths.verify!(state)
    end
  end

  test "raises when from: root::path target does not exist" do
    state =
      dsl_state([
        field(:dest, from_path: [:root, :nope])
      ])

    assert_raise Spark.Error.DslError, ~r/references `:nope`/, fn ->
      VerifyCoreKeyPaths.verify!(state)
    end
  end

  test "passes for on: path resolution (same logic as from:)" do
    state =
      dsl_state([
        field(:source),
        field(:dest, on_path: [:source])
      ])

    assert {:ok, _} = VerifyCoreKeyPaths.verify!(state)
  end

  test "raises for on: path with missing target" do
    state =
      dsl_state([
        field(:dest, on_path: [:missing])
      ])

    assert_raise Spark.Error.DslError, ~r/references `:missing`/, fn ->
      VerifyCoreKeyPaths.verify!(state)
    end
  end

  test "passes when path traverses through a sub_field" do
    state =
      dsl_state([
        sub_field(:auth, fields: [field(:role)]),
        field(:dest, from_path: [:root, :auth, :role])
      ])

    assert {:ok, _} = VerifyCoreKeyPaths.verify!(state)
  end

  test "raises when path traverses through sub_field but target leaf is missing" do
    state =
      dsl_state([
        sub_field(:auth, fields: [field(:role)]),
        field(:dest, from_path: [:root, :auth, :nonexistent_leaf])
      ])

    assert_raise Spark.Error.DslError, ~r/`:nonexistent_leaf`/, fn ->
      VerifyCoreKeyPaths.verify!(state)
    end
  end

  test "raises when path tries to descend past a leaf field" do
    state =
      dsl_state([
        field(:not_a_subfield),
        field(:dest, from_path: [:root, :not_a_subfield, :child])
      ])

    assert_raise Spark.Error.DslError, fn ->
      VerifyCoreKeyPaths.verify!(state)
    end
  end

  test "verifies paths inside a sub_field's children using sibling scope" do
    state =
      dsl_state([
        sub_field(:auth,
          fields: [
            field(:source),
            field(:dest, from_path: [:source])
          ]
        )
      ])

    assert {:ok, _} = VerifyCoreKeyPaths.verify!(state)
  end

  test "raises for invalid path inside a sub_field" do
    state =
      dsl_state([
        sub_field(:auth,
          fields: [
            field(:dest, from_path: [:nonexistent])
          ]
        )
      ])

    assert_raise Spark.Error.DslError, fn ->
      VerifyCoreKeyPaths.verify!(state)
    end
  end

  test "transform/1 (the public hook) is a no-op when strict mode is off" do
    Application.delete_env(:guarded_struct, :strict_core_key_paths)

    state =
      dsl_state([
        field(:dest, from_path: [:totally_made_up])
      ])

    # transform/1 — the @impl entrypoint — should NOT raise when env is unset
    assert {:ok, _} = VerifyCoreKeyPaths.transform(state)
  end

  test "no path declared → no error" do
    state =
      dsl_state([
        field(:plain)
      ])

    assert {:ok, _} = VerifyCoreKeyPaths.verify!(state)
  end
end
