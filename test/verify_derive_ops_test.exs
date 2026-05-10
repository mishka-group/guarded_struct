defmodule GuardedStructTest.VerifyDeriveOpsTest do
  use ExUnit.Case, async: false

  alias GuardedStruct.Transformers.VerifyDeriveOps
  alias GuardedStruct.Dsl.{Field, SubField, ConditionalField}

  setup do
    prior_validate = Application.get_env(:guarded_struct, :validate_derive)
    prior_sanitize = Application.get_env(:guarded_struct, :sanitize_derive)
    Application.delete_env(:guarded_struct, :validate_derive)
    Application.delete_env(:guarded_struct, :sanitize_derive)
    Application.put_env(:guarded_struct, :strict_derive_ops, true)

    on_exit(fn ->
      Application.delete_env(:guarded_struct, :strict_derive_ops)

      if prior_validate,
        do: Application.put_env(:guarded_struct, :validate_derive, prior_validate)

      if prior_sanitize,
        do: Application.put_env(:guarded_struct, :sanitize_derive, prior_sanitize)
    end)

    :ok
  end

  defp dsl_state(entities, module \\ FakeModule) do
    Spark.Dsl.Transformer.persist(
      %{
        [:guardedstruct] => %{
          entities: entities,
          opts: []
        }
      },
      :module,
      module
    )
  end

  defp field(name, ops) do
    %Field{name: name, type: nil, __derive_ops__: ops}
  end

  test "unknown validate op raises Spark.Error.DslError" do
    state = dsl_state([field(:name, %{validate: [:stirng]})])

    assert_raise Spark.Error.DslError, ~r/unknown derive op.*stirng/, fn ->
      VerifyDeriveOps.transform(state)
    end
  end

  test "unknown sanitize op raises Spark.Error.DslError" do
    state = dsl_state([field(:name, %{sanitize: [:triim]})])

    assert_raise Spark.Error.DslError, ~r/unknown derive op.*triim/, fn ->
      VerifyDeriveOps.transform(state)
    end
  end

  test "typo close to a known op gets a 'did you mean' suggestion" do
    state = dsl_state([field(:name, %{validate: [:stirng]})])

    err =
      assert_raise Spark.Error.DslError, fn -> VerifyDeriveOps.transform(state) end

    assert Exception.message(err) =~ "Did you mean"
    assert Exception.message(err) =~ ":string"
  end

  test "sanitize-side typo also gets a suggestion" do
    state = dsl_state([field(:name, %{sanitize: [:triim]})])

    err =
      assert_raise Spark.Error.DslError, fn -> VerifyDeriveOps.transform(state) end

    assert Exception.message(err) =~ "Did you mean"
    assert Exception.message(err) =~ ":trim"
  end

  test "completely-fabricated op name gives no suggestion (below threshold)" do
    state = dsl_state([field(:name, %{validate: [:zxqyzqyzpzxxyy]})])

    err =
      assert_raise Spark.Error.DslError, fn -> VerifyDeriveOps.transform(state) end

    refute Exception.message(err) =~ "Did you mean"
  end

  test "well-known ops pass" do
    state =
      dsl_state([
        field(:a, %{sanitize: [:trim, :downcase], validate: [:string, {:max_len, 10}]}),
        field(:b, %{validate: [:integer, {:min_len, 0}]}),
        field(:c, %{validate: [{:enum, ["a", "b", "c"]}]})
      ])

    assert {:ok, _} = VerifyDeriveOps.transform(state)
  end

  test "parameterised ops with unknown name still raise" do
    state = dsl_state([field(:x, %{validate: [{:bogus_op, 5}]})])

    assert_raise Spark.Error.DslError, ~r/unknown derive op.*bogus_op/, fn ->
      VerifyDeriveOps.transform(state)
    end
  end

  test "either= recurses into inner ops" do
    state = dsl_state([field(:x, %{validate: [%{either: [:integer, :nope_op]}]})])

    assert_raise Spark.Error.DslError, ~r/unknown derive op.*nope_op/, fn ->
      VerifyDeriveOps.transform(state)
    end
  end

  test "skipped when not strict_mode" do
    Application.delete_env(:guarded_struct, :strict_derive_ops)
    state = dsl_state([field(:name, %{validate: [:totally_made_up]})])

    assert {:ok, _} = VerifyDeriveOps.transform(state)
  end

  test "skipped when user-extension is configured" do
    Application.put_env(:guarded_struct, :validate_derive, FakePlugin)
    on_exit(fn -> Application.delete_env(:guarded_struct, :validate_derive) end)

    state = dsl_state([field(:name, %{validate: [:plugin_op]})])

    assert {:ok, _} = VerifyDeriveOps.transform(state)
  end

  test "recurses into sub_field children" do
    nested =
      %SubField{
        name: :sub,
        type: nil,
        fields: [field(:bad, %{validate: [:notathing]})],
        sub_fields: [],
        conditional_fields: []
      }

    state = dsl_state([nested])

    assert_raise Spark.Error.DslError, ~r/unknown derive op.*notathing/, fn ->
      VerifyDeriveOps.transform(state)
    end
  end

  test "recurses into conditional_field children" do
    cf =
      %ConditionalField{
        name: :cond,
        type: nil,
        fields: [field(:bad, %{validate: [:also_not_real]})],
        sub_fields: [],
        conditional_fields: []
      }

    state = dsl_state([cf])

    assert_raise Spark.Error.DslError, ~r/unknown derive op.*also_not_real/, fn ->
      VerifyDeriveOps.transform(state)
    end
  end
end
