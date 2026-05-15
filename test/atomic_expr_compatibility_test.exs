defmodule GuardedStructTest.AtomicExprCompatibilityTest do
  @moduledoc """
  Empirical verification that `GuardedStruct.AtomicClassifier`'s safe-op
  registry actually maps to real `Ash.Expr` functions the data layer can
  execute in atomic mode. Each test exercises one op end-to-end through
  a real Ash atomic update on the ETS data layer.

  If Ash adds new built-in `Ash.Query.Function` modules in a future
  release (e.g. `string_upcase`), the corresponding "rejected" test here
  will start failing — that's the signal to promote the op from unsafe
  to safe in `AtomicClassifier`.
  """

  use ExUnit.Case, async: false

  @moduletag capture_log: true

  alias GuardedStructTest.Support.TestDomain

  defmodule TrimChange do
    use Ash.Resource.Change
    require Ash.Expr

    def atomic(_changeset, _opts, _context) do
      {:atomic, %{name: Ash.Expr.expr(string_trim(^Ash.Expr.atomic_ref(:name)))}}
    end
  end

  defmodule DowncaseChange do
    use Ash.Resource.Change
    require Ash.Expr

    def atomic(_changeset, _opts, _context) do
      {:atomic, %{name: Ash.Expr.expr(string_downcase(^Ash.Expr.atomic_ref(:name)))}}
    end
  end

  defmodule UpcaseChange do
    use Ash.Resource.Change
    require Ash.Expr

    def atomic(_changeset, _opts, _context) do
      {:atomic, %{name: Ash.Expr.expr(string_upcase(^Ash.Expr.atomic_ref(:name)))}}
    end
  end

  defmodule WithTrim do
    use Ash.Resource, domain: TestDomain, data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end

    actions do
      defaults [:read, :destroy]
      create :create, accept: [:name]

      update :update do
        accept [:name]
        change TrimChange
      end
    end
  end

  defmodule WithDowncase do
    use Ash.Resource, domain: TestDomain, data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end

    actions do
      defaults [:read, :destroy]
      create :create, accept: [:name]

      update :update do
        accept [:name]
        change DowncaseChange
      end
    end
  end

  defmodule WithUpcase do
    use Ash.Resource, domain: TestDomain, data_layer: Ash.DataLayer.Ets

    ets do
      private? true
    end

    attributes do
      uuid_primary_key :id
      attribute :name, :string, public?: true
    end

    actions do
      defaults [:read, :destroy]
      create :create, accept: [:name]

      update :update do
        accept [:name]
        change UpcaseChange
      end
    end
  end

  describe "Ash.Expr functions that DO run in atomic mode" do
    test "string_trim works — proves sanitize(trim) is atomic-safe" do
      {:ok, rec} =
        WithTrim |> Ash.Changeset.for_create(:create, %{name: "hello"}) |> Ash.create()

      {:ok, updated} =
        rec
        |> Ash.Changeset.for_update(:update, %{name: "  spaces  "})
        |> Ash.update()

      assert updated.name == "spaces"
    end

    test "string_downcase works — proves sanitize(downcase) is atomic-safe" do
      {:ok, rec} =
        WithDowncase |> Ash.Changeset.for_create(:create, %{name: "hello"}) |> Ash.create()

      {:ok, updated} =
        rec
        |> Ash.Changeset.for_update(:update, %{name: "SHOUTING"})
        |> Ash.update()

      assert updated.name == "shouting"
    end
  end

  describe "Ash.Expr functions that do NOT run in atomic mode (our classifier rejects these)" do
    test "string_upcase fails — Ash.Error.Query.NoSuchFunction" do
      {:ok, rec} =
        WithUpcase |> Ash.Changeset.for_create(:create, %{name: "hello"}) |> Ash.create()

      result =
        rec
        |> Ash.Changeset.for_update(:update, %{name: "lower"})
        |> Ash.update()

      assert {:error, err} = result
      message = Exception.message(err)
      assert message =~ "NoSuchFunction" or message =~ "must be performed atomically"
    end

    test "AtomicClassifier rejects sanitize(upcase) with informative reason" do
      assert {:unsafe, msg} =
               GuardedStruct.AtomicClassifier.classify_op({:sanitize, :upcase})

      assert msg =~ "Ash.Expr"
    end

    test "AtomicClassifier rejects sanitize(capitalize) — no initcap in Ash.Expr core" do
      assert {:unsafe, msg} =
               GuardedStruct.AtomicClassifier.classify_op({:sanitize, :capitalize})

      assert msg =~ "Ash.Expr"
    end

    test "AtomicClassifier rejects HTML sanitizers (strip_tags, basic_html, html5)" do
      for op <- [:strip_tags, :basic_html, :html5] do
        assert {:unsafe, msg} =
                 GuardedStruct.AtomicClassifier.classify_op({:sanitize, op})

        assert msg =~ "HTML parsing"
      end
    end
  end
end
