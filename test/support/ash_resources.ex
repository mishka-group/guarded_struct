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
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :email, :string, allow_nil?: false, public?: true
  end
end

defmodule GuardedStructTest.AshResources.AutoWiredForm do
  @moduledoc false
  use Ash.Resource,
    domain: GuardedStructTest.Support.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [GuardedStruct.AshResource]

  ets do
    private? true
  end

  guardedstruct auto_wire: true do
    field :email, :string, enforce: true, derives: "sanitize(trim, downcase) validate(email_r)"

    sub_field :profile, :map, authorized_fields: true do
      field :nickname, :string, derives: "sanitize(trim)"
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

defmodule GuardedStructTest.AshResources.AtomicWithCounter do
  @moduledoc """
  Fixture for the three atomic-mode options when an `Ash.Expr` is in play.

    * `:login_count` — IS in guardedstruct, has a derive that needs Elixir
      (integer range). Used to demo Option A (atomic_update + expr falls
      back to imperative) and Option B (plain literal stays atomic).
    * `:last_seen_at` — NOT in guardedstruct, plain Ash attribute. Used to
      demo Option C (atomic_update + expr on a non-owned field stays
      atomic, no bail).
  """
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
      derives: "sanitize(trim, downcase) validate(email_r)"

    field :login_count, :integer,
      default: 0,
      derives: "validate(integer, min_len=0, max_len=1_000_000)"
  end

  actions do
    defaults [:read, :destroy]
    create :create, accept: [:email, :login_count]

    update :update do
      accept [:email, :login_count, :last_seen_at]
    end

    update :update_imperative do
      accept [:email, :login_count, :last_seen_at]
      require_atomic? false
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :email, :string, allow_nil?: false, public?: true
    attribute :login_count, :integer, default: 0, public?: true
    attribute :last_seen_at, :utc_datetime, public?: true
  end
end

defmodule GuardedStructTest.AshResources.AtomicEligibleUser do
  @moduledoc """
  Real-world Ash resource exercising the atomic-mode path end-to-end:
  type checks, length, comparison, regex patterns, enum, sanitize
  transforms. Updates go through `Change.atomic/3` and the resulting
  UPDATE stays atomic with the sanitized values substituted by Ash.
  """
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

defmodule GuardedStructTest.AshResources.SectionChecks do
  @moduledoc false

  def verify(attrs) do
    if Map.get(attrs, :name) == "blocked",
      do: {:error, [%{field: :name, action: :main_validator, message: "name is blocked"}]},
      else: {:ok, attrs}
  end

  def verify_profile(attrs) do
    if Map.get(attrs, :nickname) == "blocked",
      do:
        {:error, [%{field: :nickname, action: :main_validator, message: "nickname is blocked"}]},
      else: {:ok, attrs}
  end

  def validate(:ash_not_blocked, input, field) do
    if input == "blocked",
      do: {:error, field, :ash_not_blocked, "must not be blocked"},
      else: input
  end

  def sanitize(input, :ash_shout) when is_binary(input), do: String.upcase(input)
  def sanitize(input, :ash_shout), do: input
end

defmodule GuardedStructTest.AshResources.WithSectionRules do
  @moduledoc false
  use Ash.Resource,
    domain: GuardedStructTest.Support.TestDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [GuardedStruct.AshResource]

  alias GuardedStructTest.AshResources.SectionChecks

  ets do
    private? true
  end

  guardedstruct do
    auto_wire true
    main_validator {SectionChecks, :verify}
    validate_derive SectionChecks
    sanitize_derive SectionChecks

    field :name, :string, derives: "sanitize(ash_shout)"
    field :slug, :string, derives: "validate(ash_not_blocked)"
    field :score, :integer, derives: "sanitize(default_when_nil=0, clamp=[0, 100])"

    sub_field :profile, :map,
      main_validator: {SectionChecks, :verify_profile},
      do: field(:nickname, :string)
  end

  actions do
    defaults [:read, :destroy]
    create :create, accept: [:name, :slug, :score, :profile]
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :slug, :string, public?: true
    attribute :score, :integer, public?: true
    attribute :profile, :map, public?: true
  end
end

defmodule GuardedStructTest.AshResources.WithDomainRule do
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

    field :status, :string, domain: "!auth_type=Atom[admin, moderator]"
    field :note, :string, domain: "?auth_type=Atom[admin]"
    field :auth_type, :atom

    sub_field :settings, :map do
      field :mode, :string, domain: "!auth_type=Atom[admin]"
    end
  end

  actions do
    defaults [:read, :destroy]
    create :create, accept: [:status, :note, :auth_type, :settings]
  end

  attributes do
    uuid_primary_key :id
    attribute :status, :string, public?: true
    attribute :note, :string, public?: true
    attribute :auth_type, :atom, public?: true
    attribute :settings, :map, public?: true
  end
end
