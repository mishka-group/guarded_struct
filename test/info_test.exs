defmodule GuardedStructTest.InfoTest do
  use ExUnit.Case, async: true

  alias GuardedStruct.Info
  alias GuardedStructTest.Fixtures.Info.{EverythingUser, HeadersMap}

  describe "GuardedStruct.Info — existing helpers" do
    test "guardedstruct/1 returns the entity list" do
      entities = Info.guardedstruct(EverythingUser)
      assert is_list(entities)
      assert Enum.any?(entities, &match?(%GuardedStruct.Dsl.Field{name: :id}, &1))
      assert Enum.any?(entities, &match?(%GuardedStruct.Dsl.SubField{name: :address}, &1))
    end

    test "fields/1 lists every entity, struct fields first then virtuals" do
      assert Info.fields(EverythingUser) == [
               :id,
               :password,
               :nickname,
               :status,
               :metadata,
               :address,
               :billing,
               :password_confirm
             ]
    end

    test "enforce_keys/1 reflects block-level + per-field overrides" do
      keys = Info.enforce_keys(EverythingUser)
      assert :password in keys
      # `:status` has a real default → not enforced even with block enforce: true
      refute :status in keys
      # `:nickname` has explicit `enforce: false`
      refute :nickname in keys
    end

    test "fields_meta/1 + field/2 + field?/2" do
      assert is_list(Info.fields_meta(EverythingUser))
      assert %{name: :nickname, kind: :field} = Info.field(EverythingUser, :nickname)
      assert is_nil(Info.field(EverythingUser, :nope))
      assert Info.field?(EverythingUser, :address)
      refute Info.field?(EverythingUser, :nope)
    end
  end

  describe "GuardedStruct.Info — field-level helpers" do
    test "field_kind/2 reports the kind for every entity type" do
      assert Info.field_kind(EverythingUser, :id) == :field
      assert Info.field_kind(EverythingUser, :address) == :sub_field
      assert Info.field_kind(EverythingUser, :password_confirm) == :virtual_field
      assert Info.field_kind(EverythingUser, :metadata) == :dynamic_field
      assert Info.field_kind(EverythingUser, :billing) == :conditional_field
      assert Info.field_kind(EverythingUser, :nope) == nil
    end

    test "field_default/2 returns the declared default or nil" do
      assert Info.field_default(EverythingUser, :status) == "active"
      assert Info.field_default(EverythingUser, :id) == nil
      assert Info.field_default(EverythingUser, :nope) == nil
    end

    test "field_derives/2 returns the original derive string" do
      assert Info.field_derives(EverythingUser, :nickname) ==
               "validate(string, max_len=20)"

      assert Info.field_derives(EverythingUser, :id) == nil
    end

    test "field_validator/2 returns the {Mod, fn} tuple" do
      assert Info.field_validator(EverythingUser, :password) ==
               {EverythingUser.Hashers, :hash}

      assert Info.field_validator(EverythingUser, :id) == nil
    end

    test "field_auto/2 returns the auto MFA" do
      assert Info.field_auto(EverythingUser, :id) == {EverythingUser.Ids, :gen}
      assert Info.field_auto(EverythingUser, :nickname) == nil
    end

    test "enforce?/2 is true for enforced fields, false for opt-out" do
      assert Info.enforce?(EverythingUser, :password)
      # :nickname has explicit `enforce: false`
      refute Info.enforce?(EverythingUser, :nickname)
      # :status has a real default → opts out of block-level enforce
      refute Info.enforce?(EverythingUser, :status)
      refute Info.enforce?(EverythingUser, :nope)
    end

    test "virtual?/2 and dynamic?/2" do
      assert Info.virtual?(EverythingUser, :password_confirm)
      refute Info.virtual?(EverythingUser, :id)

      assert Info.dynamic?(EverythingUser, :metadata)
      refute Info.dynamic?(EverythingUser, :password_confirm)
      refute Info.dynamic?(EverythingUser, :nope)
    end
  end

  describe "GuardedStruct.Info — collection helpers" do
    test "sub_fields/1 returns only sub_field names" do
      assert Info.sub_fields(EverythingUser) == [:address]
    end

    test "virtual_fields/1 returns only virtual_field names" do
      assert Info.virtual_fields(EverythingUser) == [:password_confirm]
    end

    test "dynamic_fields/1 returns only dynamic_field names" do
      assert Info.dynamic_fields(EverythingUser) == [:metadata]
    end

    test "conditional_fields/1 returns only conditional_field names" do
      assert Info.conditional_fields(EverythingUser) == [:billing]
    end

    test "conditional_keys/1 mirrors __information__'s :conditional_keys" do
      assert Info.conditional_keys(EverythingUser) == [:billing]
    end

    test "pattern_keyed?/1 is true for regex-key modules only" do
      assert Info.pattern_keyed?(HeadersMap)
      refute Info.pattern_keyed?(EverythingUser)
    end
  end

  describe "GuardedStruct.Info — section-option shorthands" do
    test "enforce?/1 reflects section `enforce:`" do
      assert Info.enforce?(EverythingUser)
      refute Info.enforce?(HeadersMap)
    end

    test "authorized_fields?/1 reflects section `authorized_fields:`" do
      assert Info.authorized_fields?(EverythingUser)
      refute Info.authorized_fields?(HeadersMap)
    end

    test "json?/1 reflects section `json:`" do
      assert Info.json?(EverythingUser)
      refute Info.json?(HeadersMap)
    end

    test "opaque?/1 defaults to false" do
      refute Info.opaque?(EverythingUser)
    end

    test "error?/1 defaults to false" do
      refute Info.error?(EverythingUser)
    end
  end

  describe "GuardedStruct.Info — navigation" do
    test "sub_module/2 returns the generated submodule for a sub_field" do
      assert Info.sub_module(EverythingUser, :address) ==
               EverythingUser.Address

      # Force-load — sub_field submodules come from async_compile.
      assert Code.ensure_loaded?(EverythingUser.Address)
      assert function_exported?(EverythingUser.Address, :builder, 1)
      assert function_exported?(EverythingUser.Address, :__fields__, 0)
    end

    test "sub_module/2 returns nil for non-sub_field names" do
      assert Info.sub_module(EverythingUser, :id) == nil
      assert Info.sub_module(EverythingUser, :password_confirm) == nil
      assert Info.sub_module(EverythingUser, :nope) == nil
    end

    test "conditional_children/2 returns the variant list" do
      children = Info.conditional_children(EverythingUser, :billing)
      assert is_list(children)
      assert length(children) == 2

      # Both children share the parent's name; their kinds differ
      kinds = children |> Enum.map(& &1.kind) |> Enum.sort()
      assert kinds == [:field, :sub_field]
    end

    test "conditional_children/2 returns nil for non-conditional names" do
      assert Info.conditional_children(EverythingUser, :id) == nil
      assert Info.conditional_children(EverythingUser, :address) == nil
      assert Info.conditional_children(EverythingUser, :nope) == nil
    end
  end

  describe "GuardedStruct.Info — mixed usage" do
    test "user can compute 'required, non-virtual, non-dynamic' fields" do
      required_real_fields =
        EverythingUser
        |> Info.fields()
        |> Enum.filter(fn name ->
          Info.enforce?(EverythingUser, name) and
            not Info.virtual?(EverythingUser, name) and
            not Info.dynamic?(EverythingUser, name)
        end)

      # :id and :password are enforced (block-level enforce: true); :status
      # has a default; :nickname is enforce: false; sub_field :address is
      # enforced. Conditional :billing inherits block enforce.
      assert :password in required_real_fields
      assert :address in required_real_fields
      refute :status in required_real_fields
      refute :nickname in required_real_fields
      refute :password_confirm in required_real_fields
      refute :metadata in required_real_fields
    end

    test "user can walk every sub_field into its generated module" do
      sub_modules =
        EverythingUser
        |> Info.sub_fields()
        |> Enum.map(&Info.sub_module(EverythingUser, &1))

      assert sub_modules == [EverythingUser.Address]
    end

    test "the submodule itself is introspectable" do
      # Sub_field submodules aren't Spark DSL modules — only the
      # `__fields__/0`-based helpers work on them.
      assert Info.fields(EverythingUser.Address) == [:city, :zip]
      assert Info.enforce?(EverythingUser.Address, :city)
      assert Info.field_kind(EverythingUser.Address, :city) == :field
      refute Info.pattern_keyed?(EverythingUser.Address)
    end

    test "Spark-generated accessor still works (compat with manual usage)" do
      assert Info.guardedstruct_enforce!(EverythingUser) == true
      assert Info.guardedstruct_json!(EverythingUser) == true
    end
  end

  describe "GuardedStruct.Info.describe/1 — full dump" do
    test "top-level dump has every documented top-level key" do
      d = Info.describe(EverythingUser)

      assert Map.keys(d) |> Enum.sort() == [
               :conditional_keys,
               :enforce_keys,
               :fields,
               :key,
               :keys,
               :module,
               :options,
               :path,
               :pattern_keyed?,
               :patterns,
               :shape
             ]
    end

    test "top-level identity fields are correct" do
      d = Info.describe(EverythingUser)
      assert d.module == EverythingUser
      assert d.path == []
      assert d.key == :root
      assert d.shape == :struct
      refute d.pattern_keyed?
      assert d.patterns == []
    end

    test "options map includes EVERY section option key" do
      opts = Info.describe(EverythingUser).options

      assert Map.keys(opts) |> Enum.sort() == [
               :authorized_fields,
               :enforce,
               :error,
               :json,
               :main_validator,
               :module,
               :opaque,
               :sanitize_derive,
               :validate_derive
             ]

      # Declared values
      assert opts.enforce == true
      assert opts.authorized_fields == true
      assert opts.json == true
      # Defaults and undeclared options
      assert opts.opaque == false
      assert opts.error == false
      assert opts.module == nil
      assert opts.main_validator == nil
      assert opts.validate_derive == nil
      assert opts.sanitize_derive == nil
    end

    test "fields list has one entry per declared entity (in canonical order)" do
      names = Info.describe(EverythingUser).fields |> Enum.map(& &1.name)

      assert names == [
               :id,
               :password,
               :nickname,
               :status,
               :metadata,
               :address,
               :billing,
               :password_confirm
             ]
    end

    test "each field meta carries kind + enforce? + type + every entity option" do
      fields = Info.describe(EverythingUser).fields
      by_name = Map.new(fields, &{&1.name, &1})

      id = by_name[:id]
      assert id.kind == :field
      assert id.type == "String.t()"
      assert id.auto == {EverythingUser.Ids, :gen}
      assert id.enforce? == true

      nickname = by_name[:nickname]
      assert nickname.kind == :field
      assert nickname.enforce == false
      assert nickname.enforce? == false
      assert nickname.derive == "validate(string, max_len=20)"
      assert is_map(nickname.__derive_ops__)
      assert :validate in Map.keys(nickname.__derive_ops__)

      status = by_name[:status]
      assert status.default == "active"
      assert status.enforce? == false

      pc = by_name[:password_confirm]
      assert pc.kind == :virtual_field
      refute pc.enforce?
      refute Map.has_key?(pc, :sub_module)

      meta = by_name[:metadata]
      assert meta.kind == :dynamic_field

      address = by_name[:address]
      assert address.kind == :sub_field
      assert address.sub_module == EverythingUser.Address
      assert address.enforce? == true
      assert address.list? == false

      billing = by_name[:billing]
      assert billing.kind == :conditional_field
      assert is_list(billing.children)
      assert length(billing.children) == 2
    end

    test "submodule dump uses :path and limited :options" do
      d = Info.describe(EverythingUser.Address)
      assert d.module == EverythingUser.Address
      refute d.path == []
      # `:key` is the camelized last path segment, not the field atom.
      assert d.key == :Address
      assert d.shape == :struct
      assert :city in d.keys
      assert :city in d.enforce_keys

      assert Map.keys(d.options) |> Enum.sort() == [
               :authorized_fields,
               :enforce,
               :error,
               :json,
               :main_validator,
               :module,
               :opaque,
               :sanitize_derive,
               :validate_derive
             ]

      assert d.options.enforce == nil
      assert d.options.opaque == nil
    end

    test "pattern-keyed module dump reflects :pattern_map shape" do
      d = Info.describe(HeadersMap)
      assert d.shape == :pattern_map
      assert d.pattern_keyed? == true
      assert length(d.patterns) == 1
      assert d.keys == []
      assert d.enforce_keys == []

      [meta] = d.fields
      assert meta.kind == :pattern_field
      assert is_struct(meta.pattern, Regex)
    end

    test "no information is lost: type + raw enforce are now exposed" do
      id_meta = Info.field(EverythingUser, :id)
      assert id_meta.type == "String.t()"

      nick_meta = Info.field(EverythingUser, :nickname)
      assert nick_meta.enforce == false
    end
  end
end
