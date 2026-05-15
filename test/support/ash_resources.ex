defmodule GuardedStructTest.AshResources.Manual do
  @moduledoc false
  use Ash.Resource,
    domain: GuardedStructTest.Support.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [GuardedStruct.AshResource]

  ets do
    private? true
  end

  guardedstruct do
    field :email, :string,
      enforce: true,
      derives: "sanitize(trim, downcase) validate(string, not_empty, email_r)"

    field :nickname, :string, derives: "sanitize(trim) validate(string, max_len=20)"
  end

  actions do
    defaults [:read, :destroy]
    create :create, accept: [:email, :nickname]

    update :update do
      accept [:email, :nickname]
      require_atomic? false
    end
  end

  changes do
    change GuardedStruct.AshResource.Change
  end

  attributes do
    uuid_primary_key :id
    attribute :email, :string, allow_nil?: false, public?: true
    attribute :nickname, :string, public?: true
  end
end

defmodule GuardedStructTest.AshResources.AutoWired do
  @moduledoc false
  use Ash.Resource,
    domain: GuardedStructTest.Support.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [GuardedStruct.AshResource]

  ets do
    private? true
  end

  guardedstruct do
    auto_wire true

    field :email, :string,
      enforce: true,
      derives: "sanitize(trim, downcase) validate(string, not_empty, email_r)"
  end

  actions do
    defaults [:read, :destroy]
    create :create, accept: [:email]

    update :update do
      accept [:email]
      require_atomic? false
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :email, :string, allow_nil?: false, public?: true
  end
end

defmodule GuardedStructTest.AshResources.AutoWireOff do
  @moduledoc false
  use Ash.Resource,
    domain: GuardedStructTest.Support.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [GuardedStruct.AshResource]

  ets do
    private? true
  end

  guardedstruct do
    auto_wire false
    field :email, :string, enforce: true, derives: "validate(string)"
  end

  actions do
    defaults [:read, :destroy]
    create :create, accept: [:email]
  end

  attributes do
    uuid_primary_key :id
    attribute :email, :string, allow_nil?: false, public?: true
  end
end

defmodule GuardedStructTest.AshResources.UserManual do
  @moduledoc "Manually-wired resource (changes do change ... end)"
  use Ash.Resource,
    domain: GuardedStructTest.Support.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [GuardedStruct.AshResource]

  ets do
    private? true
  end

  guardedstruct do
    field :email, :string,
      enforce: true,
      derives: "sanitize(trim, downcase) validate(string, not_empty, email_r, max_len=320)"

    field :nickname, :string, derives: "sanitize(trim) validate(string, max_len=20)"
  end

  actions do
    defaults [:read, :destroy]
    create :create, accept: [:email, :nickname]

    update :update do
      accept [:email, :nickname]
      require_atomic? false
    end
  end

  changes do
    change GuardedStruct.AshResource.Change
  end

  attributes do
    uuid_primary_key :id
    attribute :email, :string, allow_nil?: false, public?: true
    attribute :nickname, :string, public?: true
  end
end

defmodule GuardedStructTest.AshResources.UserAuto do
  @moduledoc "Auto-wired equivalent — must behave the same as UserManual"
  use Ash.Resource,
    domain: GuardedStructTest.Support.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [GuardedStruct.AshResource]

  ets do
    private? true
  end

  guardedstruct do
    auto_wire true

    field :email, :string,
      enforce: true,
      derives: "sanitize(trim, downcase) validate(string, not_empty, email_r, max_len=320)"

    field :nickname, :string, derives: "sanitize(trim) validate(string, max_len=20)"
  end

  actions do
    defaults [:read, :destroy]
    create :create, accept: [:email, :nickname]

    update :update do
      accept [:email, :nickname]
      require_atomic? false
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :email, :string, allow_nil?: false, public?: true
    attribute :nickname, :string, public?: true
  end
end

defmodule GuardedStructTest.AshResources.WithSubField do
  @moduledoc "Resource with a nested sub_field stored in a :map attribute"
  use Ash.Resource,
    domain: GuardedStructTest.Support.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [GuardedStruct.AshResource]

  ets do
    private? true
  end

  guardedstruct do
    auto_wire true

    field :email, :string, derives: "validate(email_r)"

    sub_field :profile, :map do
      field :name, :string, derives: "sanitize(trim)"
      field :bio, :string, derives: "validate(string, max_len=200)"

      sub_field :address, :map do
        field :city, :string, derives: "sanitize(trim)"

        sub_field :geo, :map do
          field :lat, :float
          field :lng, :float
        end
      end
    end
  end

  actions do
    defaults [:read, :destroy]
    create :create, accept: [:email, :profile]
  end

  attributes do
    uuid_primary_key :id
    attribute :email, :string, allow_nil?: false, public?: true
    attribute :profile, :map, public?: true
  end
end

defmodule GuardedStructTest.AshResources.WithListSubField do
  @moduledoc "Resource with list-of-sub_field stored as list of maps"
  use Ash.Resource,
    domain: GuardedStructTest.Support.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [GuardedStruct.AshResource]

  ets do
    private? true
  end

  guardedstruct do
    auto_wire true

    field :name, :string

    sub_field :tags, :map do
      structs true
      field :label, :string, derives: "sanitize(trim, downcase)"
      field :score, :integer
    end
  end

  actions do
    defaults [:read, :destroy]
    create :create, accept: [:name, :tags]
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :tags, {:array, :map}, public?: true
  end
end

defmodule GuardedStructTest.AshResources.WithAshChange do
  @moduledoc "Resource that COMBINES our change with Ash's own change"
  use Ash.Resource,
    domain: GuardedStructTest.Support.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [GuardedStruct.AshResource]

  ets do
    private? true
  end

  guardedstruct do
    auto_wire true
    field :email, :string, derives: "sanitize(trim, downcase) validate(email_r)"
  end

  actions do
    defaults [:read, :destroy]
    create :create, accept: [:email]
  end

  # Ash's own change running alongside ours.
  changes do
    change fn cs, _ ->
      email = Ash.Changeset.get_attribute(cs, :email)
      slug = if email, do: email |> String.split("@") |> hd(), else: nil
      Ash.Changeset.force_change_attribute(cs, :slug, slug)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :email, :string, allow_nil?: false, public?: true
    attribute :slug, :string, public?: true
  end
end

defmodule GuardedStructTest.AshResources.AtomicEligibleUser do
  @moduledoc """
  Real-world Ash resource that opts into atomic mode (`atomic: true`)
  and exercises every atomic-safe op category — type checks, length,
  comparison, regex patterns, enum, sanitize transforms. All ops in
  this resource are in `GuardedStruct.AtomicClassifier`'s safe registry,
  so the compile-time `VerifyAtomic` verifier accepts it.
  """
  use Ash.Resource,
    domain: GuardedStructTest.Support.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [GuardedStruct.AshResource]

  ets do
    private? true
  end

  guardedstruct do
    atomic true
    auto_wire true

    field :email, :string,
      derives: "sanitize(trim, downcase) validate(string, not_empty, email_r, max_len=320)"

    field :username, :string,
      derives: "sanitize(trim, downcase) validate(string, not_empty, min_len=3, max_len=20)"

    field :age, :integer, derives: "validate(integer, min_len=0, max_len=150)"

    field :role, :string, derives: "sanitize(trim) validate(enum=String[admin::user::guest])"

    field :tenant_id, :string, derives: "validate(uuid)"

    field :country_code, :string,
      derives: "sanitize(trim, downcase) validate(string, min_len=2, max_len=2)"

    field :status, :string,
      default: "active",
      derives: "validate(enum=String[active::archived::pending])"
  end

  actions do
    defaults [:read, :destroy]

    create :create, accept: [:email, :username, :age, :role, :tenant_id, :country_code, :status]

    update :update do
      accept [:email, :username, :age, :role, :status]
      require_atomic? false
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :email, :string, allow_nil?: false, public?: true
    attribute :username, :string, allow_nil?: false, public?: true
    attribute :age, :integer, public?: true
    attribute :role, :string, public?: true
    attribute :tenant_id, :string, public?: true
    attribute :country_code, :string, public?: true
    attribute :status, :string, public?: true
  end
end
