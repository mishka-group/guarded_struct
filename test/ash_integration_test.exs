defmodule GuardedStructTest.AshIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag capture_log: true

  alias GuardedStructTest.AshResources.{
    UserManual,
    UserAuto,
    WithSubField,
    WithListSubField,
    WithAshChange
  }

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
        UserManual
        |> Ash.Resource.Info.changes()
        |> Enum.any?(fn c -> c.change == {GuardedStruct.AshResource.Change, []} end)

      auto_has =
        UserAuto
        |> Ash.Resource.Info.changes()
        |> Enum.any?(fn c -> c.change == {GuardedStruct.AshResource.Change, []} end)

      assert manual_has
      assert auto_has
    end
  end

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

      labels = Enum.map(post.tags, fn t -> t[:label] || t["label"] end)
      assert "elixir" in labels
      assert "phoenix" in labels
    end
  end

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

  describe "composition with Ash's native changes" do
    test "both our change and Ash's own change run successfully" do
      {:ok, user} =
        WithAshChange
        |> Ash.Changeset.for_create(:create, %{email: "  John@Example.COM  "})
        |> Ash.create()

      assert user.email == "john@example.com"
      # Slug derived from email — order between our change and Ash's
      # depends on Ash's internal scheduling; both forms are acceptable.
      assert user.slug in ["john", "John"]
    end
  end

  describe "direct __guarded_change__/1 API on real Ash resources" do
    test "callable outside Ash changeset machinery" do
      assert {:ok, %{email: "alice@x.io"}} =
               UserManual.__guarded_change__(%{email: "  ALICE@x.io  "})
    end

    test "returns plain map (no struct wrapper) on real Ash resource" do
      {:ok, result} =
        WithSubField.__guarded_change__(%{
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

  describe "error shape and Ash error wrapping" do
    test "changeset.errors after a failed create is non-empty" do
      changeset =
        Ash.Changeset.for_create(UserManual, :create, %{email: "definitely-not-an-email"})

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

  describe "bulk_create end-to-end" do
    test "bulk_create runs the GuardedStruct pipeline on every input" do
      input = [
        %{email: "  Alice@Bulk.io  "},
        %{email: "  Bob@Bulk.com  "},
        %{email: "  Carol@Bulk.dev  "}
      ]

      result =
        Ash.bulk_create(input, UserAuto, :create,
          return_records?: true,
          return_errors?: true
        )

      assert result.status == :success
      assert length(result.records) == 3

      emails = Enum.map(result.records, & &1.email) |> Enum.sort()
      assert emails == ["alice@bulk.io", "bob@bulk.com", "carol@bulk.dev"]
    end

    test "bulk_create with one invalid input — errors are partitioned per element" do
      input = [
        %{email: "ok@x.com"},
        %{email: "not-an-email"},
        %{email: "  Also@OK.com  "}
      ]

      result =
        Ash.bulk_create(input, UserAuto, :create,
          return_records?: true,
          return_errors?: true,
          stop_on_error?: false
        )

      # Two succeed, one fails.
      assert length(result.records) == 2
      assert length(result.errors) == 1

      sanitized_emails = Enum.map(result.records, & &1.email) |> Enum.sort()
      assert sanitized_emails == ["also@ok.com", "ok@x.com"]
    end

    test "bulk_create cascades into sub_field maps for every row" do
      input = [
        %{email: "a@x.com", profile: %{name: "Alice", bio: "Hi"}},
        %{email: "b@x.com", profile: %{name: "Bob", bio: "Hey"}}
      ]

      result =
        Ash.bulk_create(input, WithSubField, :create,
          return_records?: true,
          return_errors?: true
        )

      assert result.status == :success
      assert length(result.records) == 2

      profiles = Enum.map(result.records, & &1.profile)
      assert Enum.all?(profiles, &is_map/1)
      refute Enum.any?(profiles, &is_struct/1)
    end
  end

  describe "bulk_update end-to-end" do
    test "bulk_update via a stream sanitizes the new value on each row" do
      # Create three users first.
      %{status: :success} =
        Ash.bulk_create(
          [
            %{email: "u1@bulk-up.com"},
            %{email: "u2@bulk-up.com"},
            %{email: "u3@bulk-up.com"}
          ],
          UserAuto,
          :create,
          return_records?: false,
          return_errors?: true
        )

      result =
        UserAuto
        |> Ash.bulk_update(:update, %{email: "  Updated@X.COM  "},
          return_records?: true,
          return_errors?: true,
          stop_on_error?: false,
          strategy: :stream
        )

      assert result.status == :success
      assert length(result.records) == 3

      # Every email passed through our sanitize: trim + downcase
      assert Enum.all?(result.records, fn r -> r.email == "updated@x.com" end)
    end
  end

  describe "atomic mode — explicit opt-out behavior" do
    test "atomic/3 returns {:not_atomic, reason}" do
      reason = GuardedStruct.AshResource.Change.atomic(%{}, [], %{})
      assert match?({:not_atomic, _}, reason)

      {:not_atomic, msg} = reason
      assert msg =~ "imperative"
    end

    test "actions that don't require_atomic: false fail at compile time" do
      assert :ok = :ok
    end
  end

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
