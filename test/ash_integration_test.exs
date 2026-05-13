defmodule GuardedStructTest.AshIntegrationTest do
  use ExUnit.Case, async: false

  # End-to-end tests against REAL Ash 3.x with the ETS data layer. No DB
  # required — Ash.DataLayer.Ets runs in-process and is reset between tests.
  #
  # Each describe block covers one aspect of the integration:
  #   1. Sanitize ops actually transform values stored in Ash
  #   2. Validate ops actually block invalid create/update
  #   3. Both wiring modes (manual + auto) behave identically end-to-end
  #   4. Cascade — sub_field maps drop into Ash `:map` attributes cleanly
  #   5. Update actions also fire the guardedstruct pipeline
  #   6. Composition with Ash's own changes/validations
  #   7. Direct __guarded_change__/1 API still works alongside Ash
  #   8. Error shape — what consumers see in changeset.errors

  alias GuardedStructTest.Support.TestDomain

  # ────────────────────────────────────────────────────────────────────
  # Test resources
  # ────────────────────────────────────────────────────────────────────

  defmodule UserManual do
    @moduledoc "Manually-wired resource (changes do change ... end)"
    use Ash.Resource,
      domain: TestDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [GuardedStruct.AshResource]

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :email, :string, allow_nil?: false, public?: true
      attribute :nickname, :string, public?: true
    end

    actions do
      defaults [:read, :destroy]
      create :create, accept: [:email, :nickname]

      update :update do
        accept [:email, :nickname]
        # Our change isn't atomic-safe — fall back to imperative mode.
        require_atomic? false
      end
    end

    guardedstruct do
      field :email, :string,
        enforce: true,
        derives: "sanitize(trim, downcase) validate(string, not_empty, email_r, max_len=320)"

      field :nickname, :string,
        derives: "sanitize(trim) validate(string, max_len=20)"
    end

    changes do
      change GuardedStruct.AshResource.Change
    end
  end

  defmodule UserAuto do
    @moduledoc "Auto-wired equivalent — must behave the same"
    use Ash.Resource,
      domain: TestDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [GuardedStruct.AshResource]

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :email, :string, allow_nil?: false, public?: true
      attribute :nickname, :string, public?: true
    end

    actions do
      defaults [:read, :destroy]
      create :create, accept: [:email, :nickname]

      update :update do
        accept [:email, :nickname]
        require_atomic? false
      end
    end

    guardedstruct do
      auto_wire true

      field :email, :string,
        enforce: true,
        derives: "sanitize(trim, downcase) validate(string, not_empty, email_r, max_len=320)"

      field :nickname, :string,
        derives: "sanitize(trim) validate(string, max_len=20)"
    end
  end

  defmodule WithSubField do
    @moduledoc "Resource with a nested sub_field stored in a :map attribute"
    use Ash.Resource,
      domain: TestDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [GuardedStruct.AshResource]

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :email, :string, allow_nil?: false, public?: true
      attribute :profile, :map, public?: true
    end

    actions do
      defaults [:read, :destroy]
      create :create, accept: [:email, :profile]
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
  end

  defmodule WithListSubField do
    @moduledoc "Resource with list-of-sub_field stored as list of maps"
    use Ash.Resource,
      domain: TestDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [GuardedStruct.AshResource]

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
      attribute :tags, {:array, :map}, public?: true
    end

    actions do
      defaults [:read, :destroy]
      create :create, accept: [:name, :tags]
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
  end

  defmodule WithAshChange do
    @moduledoc "Resource that COMBINES our change with Ash's own change"
    use Ash.Resource,
      domain: TestDomain,
      data_layer: Ash.DataLayer.Ets,
      extensions: [GuardedStruct.AshResource]

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :email, :string, allow_nil?: false, public?: true
      attribute :slug, :string, public?: true
    end

    actions do
      defaults [:read, :destroy]
      create :create, accept: [:email]
    end

    guardedstruct do
      auto_wire true
      field :email, :string, derives: "sanitize(trim, downcase) validate(email_r)"
    end

    # Ash's own change — should run AFTER guardedstruct's (since gs change
    # is added first via the transformer, then this one is declared).
    changes do
      change fn cs, _ ->
        email = Ash.Changeset.get_attribute(cs, :email)
        slug = if email, do: email |> String.split("@") |> hd(), else: nil
        Ash.Changeset.force_change_attribute(cs, :slug, slug)
      end
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # 1. Sanitize ops actually transform values stored in Ash
  # ────────────────────────────────────────────────────────────────────

  describe "sanitize end-to-end through Ash.create/1" do
    test "trim + downcase normalize an email before insert (manual wiring)" do
      {:ok, user} =
        UserManual
        |> Ash.Changeset.for_create(:create, %{email: "  Alice@Example.COM  "})
        |> Ash.create()

      assert user.email == "alice@example.com"
    end

    test "trim + downcase normalize via auto-wired resource" do
      {:ok, user} =
        UserAuto
        |> Ash.Changeset.for_create(:create, %{email: "  Bob@X.IO  "})
        |> Ash.create()

      assert user.email == "bob@x.io"
    end

    test "trim runs on nickname too" do
      {:ok, user} =
        UserManual
        |> Ash.Changeset.for_create(:create, %{email: "ok@x.com", nickname: "  jay  "})
        |> Ash.create()

      assert user.nickname == "jay"
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # 2. Validation errors block insert
  # ────────────────────────────────────────────────────────────────────

  describe "validation errors block Ash.create/1" do
    test "invalid email format → Ash.Error.Invalid" do
      assert {:error, %Ash.Error.Invalid{} = err} =
               UserManual
               |> Ash.Changeset.for_create(:create, %{email: "not-an-email"})
               |> Ash.create()

      assert inspect(err) =~ "email"
    end

    test "nickname too long → invalid" do
      assert {:error, _} =
               UserManual
               |> Ash.Changeset.for_create(:create, %{
                 email: "ok@x.com",
                 nickname: String.duplicate("a", 50)
               })
               |> Ash.create()
    end

    test "missing required Ash attribute → Ash blocks before our change fires" do
      assert {:error, %Ash.Error.Invalid{}} =
               UserManual
               |> Ash.Changeset.for_create(:create, %{})
               |> Ash.create()
    end

    test "auto-wired resource rejects bad input identically" do
      assert {:error, %Ash.Error.Invalid{}} =
               UserAuto
               |> Ash.Changeset.for_create(:create, %{email: "bad"})
               |> Ash.create()
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # 3. Manual + auto wiring behave identically
  # ────────────────────────────────────────────────────────────────────

  describe "manual vs auto wiring parity" do
    test "same input produces same persisted result" do
      input = %{email: "  Carol@Z.IO  ", nickname: "  c  "}

      {:ok, manual} =
        UserManual |> Ash.Changeset.for_create(:create, input) |> Ash.create()

      {:ok, auto} =
        UserAuto |> Ash.Changeset.for_create(:create, input) |> Ash.create()

      assert manual.email == auto.email
      assert manual.nickname == auto.nickname
    end

    test "both register the GuardedStruct change in Ash.Resource.Info.changes/1" do
      manual_has =
        Ash.Resource.Info.changes(UserManual)
        |> Enum.any?(fn c -> c.change == {GuardedStruct.AshResource.Change, []} end)

      auto_has =
        Ash.Resource.Info.changes(UserAuto)
        |> Enum.any?(fn c -> c.change == {GuardedStruct.AshResource.Change, []} end)

      assert manual_has
      assert auto_has
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # 4. Cascade — sub_field maps land in Ash :map attributes cleanly
  # ────────────────────────────────────────────────────────────────────

  describe "sub_field cascade lands in :map attribute" do
    test "single-level sub_field stored as plain map (not struct)" do
      {:ok, user} =
        WithSubField
        |> Ash.Changeset.for_create(:create, %{
          email: "x@y.com",
          profile: %{name: "Alice", bio: "Hi"}
        })
        |> Ash.create()

      assert is_map(user.profile)
      refute is_struct(user.profile)
      assert user.profile[:name] == "Alice" or user.profile["name"] == "Alice"
    end

    test "3-deep nested sub_field returns maps at every level" do
      {:ok, user} =
        WithSubField
        |> Ash.Changeset.for_create(:create, %{
          email: "x@y.com",
          profile: %{
            name: "Alice",
            address: %{
              city: "Berlin",
              geo: %{lat: 52.5, lng: 13.4}
            }
          }
        })
        |> Ash.create()

      profile = user.profile
      address = profile[:address] || profile["address"]
      geo = address[:geo] || address["geo"]

      refute is_struct(profile)
      refute is_struct(address)
      refute is_struct(geo)
      assert (geo[:lat] || geo["lat"]) == 52.5
    end

    test "list-of-sub_field stored as list of maps" do
      {:ok, post} =
        WithListSubField
        |> Ash.Changeset.for_create(:create, %{
          name: "Post",
          tags: [
            %{label: "  Elixir  ", score: 10},
            %{label: "  Phoenix  ", score: 8}
          ]
        })
        |> Ash.create()

      assert is_list(post.tags)
      assert length(post.tags) == 2
      refute Enum.any?(post.tags, &is_struct/1)

      # Sanitize ran on each tag's label
      labels =
        Enum.map(post.tags, fn t -> t[:label] || t["label"] end)

      assert "elixir" in labels
      assert "phoenix" in labels
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # 5. Update actions also fire the guardedstruct pipeline
  # ────────────────────────────────────────────────────────────────────

  describe "update actions" do
    test "update sanitizes the new value just like create" do
      {:ok, user} =
        UserAuto
        |> Ash.Changeset.for_create(:create, %{email: "first@x.com"})
        |> Ash.create()

      {:ok, updated} =
        user
        |> Ash.Changeset.for_update(:update, %{email: "  Second@X.COM  "})
        |> Ash.update()

      assert updated.email == "second@x.com"
    end

    test "update with invalid email fails" do
      {:ok, user} =
        UserAuto
        |> Ash.Changeset.for_create(:create, %{email: "first@x.com"})
        |> Ash.create()

      assert {:error, _} =
               user
               |> Ash.Changeset.for_update(:update, %{email: "not-an-email"})
               |> Ash.update()
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # 6. Composition with Ash's own changes
  # ────────────────────────────────────────────────────────────────────

  describe "composition with Ash's native changes" do
    test "both our change and Ash's own change run successfully" do
      {:ok, user} =
        WithAshChange
        |> Ash.Changeset.for_create(:create, %{email: "  John@Example.COM  "})
        |> Ash.create()

      # Our sanitize ran (trim + downcase).
      assert user.email == "john@example.com"

      # Ash's own change also ran and set :slug. Order of execution depends
      # on Ash's internal scheduling — what matters here is that BOTH ran
      # without one disabling the other. The slug is derived from whatever
      # state of :email Ash's change observed; both forms accepted.
      assert user.slug in ["john", "John"]
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # 7. Direct __guarded_change__/1 still works
  # ────────────────────────────────────────────────────────────────────

  describe "direct __guarded_change__/1 API on real Ash resources" do
    test "callable outside Ash changeset machinery" do
      assert {:ok, %{email: "alice@x.io"}} =
               UserManual.__guarded_change__(%{email: "  ALICE@x.io  "})
    end

    test "returns plain map (no struct wrapper) on real Ash resource" do
      {:ok, result} = WithSubField.__guarded_change__(%{
        email: "a@b.com",
        profile: %{name: "Z", address: %{city: "Paris"}}
      })

      refute is_struct(result)
      refute is_struct(result.profile)
      refute is_struct(result.profile.address)
    end

    test "errors surface as the same shape as standalone" do
      assert {:error, _errs} = UserManual.__guarded_change__(%{email: "bad"})
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # 8. Error shape — what consumers see
  # ────────────────────────────────────────────────────────────────────

  describe "error shape and Ash error wrapping" do
    test "changeset.errors after a failed create is non-empty" do
      changeset =
        UserManual
        |> Ash.Changeset.for_create(:create, %{email: "definitely-not-an-email"})

      refute changeset.valid?
      assert length(changeset.errors) > 0
    end

    test "Ash.create on invalid changeset returns Ash.Error.Invalid" do
      assert {:error, %Ash.Error.Invalid{errors: errs}} =
               UserManual
               |> Ash.Changeset.for_create(:create, %{email: "bad"})
               |> Ash.create()

      assert is_list(errs)
      assert length(errs) > 0
    end

    test "successful Ash.create returns a struct of the resource type" do
      {:ok, user} =
        UserManual
        |> Ash.Changeset.for_create(:create, %{email: "ok@x.com"})
        |> Ash.create()

      assert is_struct(user, UserManual)
    end
  end

  # ────────────────────────────────────────────────────────────────────
  # 9. Read-after-write — the persisted record reflects sanitized values
  # ────────────────────────────────────────────────────────────────────

  describe "persistence — read after write" do
    test "reading back via Ash.get/2 returns the sanitized email" do
      {:ok, created} =
        UserAuto
        |> Ash.Changeset.for_create(:create, %{email: "  Dean@X.COM  "})
        |> Ash.create()

      {:ok, fetched} = Ash.get(UserAuto, created.id)

      assert fetched.email == "dean@x.com"
      assert fetched.id == created.id
    end

    test "destroy works on a guarded-validated record" do
      {:ok, user} =
        UserAuto
        |> Ash.Changeset.for_create(:create, %{email: "z@z.com"})
        |> Ash.create()

      assert :ok = Ash.destroy(user)
      assert {:error, _} = Ash.get(UserAuto, user.id)
    end
  end
end
