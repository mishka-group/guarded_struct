defmodule GuardedStructTest.InfoTest do
  use ExUnit.Case, async: true

  defmodule TestUser do
    use GuardedStruct

    guardedstruct enforce: true, authorized_fields: true do
      field(:id, :integer, default: 0)
      field(:name, String.t())
      field(:nickname, String.t(), enforce: false, derives: "validate(string, max_len=20)")

      sub_field(:profile, :map) do
        field(:bio, :string)
      end
    end
  end

  describe "GuardedStruct.Info" do
    test "guardedstruct/1 returns the entity list" do
      entities = GuardedStruct.Info.guardedstruct(TestUser)
      assert is_list(entities)
      assert Enum.any?(entities, &match?(%GuardedStruct.Dsl.Field{name: :name}, &1))
      assert Enum.any?(entities, &match?(%GuardedStruct.Dsl.SubField{name: :profile}, &1))
    end

    test "fields/1 returns declared field names in order" do
      assert GuardedStruct.Info.fields(TestUser) == [:id, :name, :nickname, :profile]
    end

    test "enforce_keys/1 reflects per-field + block-level enforce" do
      keys = GuardedStruct.Info.enforce_keys(TestUser)
      assert :name in keys
      # `:nickname` has explicit `enforce: false` → not enforced
      refute :nickname in keys
      # `:id` has `default: 0` → not enforced even with block enforce: true
      refute :id in keys
    end

    test "fields_meta/1 returns runtime field metadata" do
      meta = GuardedStruct.Info.fields_meta(TestUser)
      assert is_list(meta)
      name_meta = Enum.find(meta, &(&1.name == :name))
      assert name_meta.kind == :field

      profile_meta = Enum.find(meta, &(&1.name == :profile))
      assert profile_meta.kind == :sub_field
    end

    test "field/2 returns the meta for a single field" do
      assert %{kind: :field, name: :nickname} = GuardedStruct.Info.field(TestUser, :nickname)
      assert is_nil(GuardedStruct.Info.field(TestUser, :no_such_field))
    end

    test "field?/2 boolean membership" do
      assert GuardedStruct.Info.field?(TestUser, :name)
      assert GuardedStruct.Info.field?(TestUser, :profile)
      refute GuardedStruct.Info.field?(TestUser, :no_such_field)
    end

    test "Spark-generated guardedstruct_enforce!/1 returns the section option" do
      assert GuardedStruct.Info.guardedstruct_enforce!(TestUser) == true
    end

    test "Spark-generated guardedstruct_authorized_fields!/1 returns the section option" do
      assert GuardedStruct.Info.guardedstruct_authorized_fields!(TestUser) == true
    end
  end
end
