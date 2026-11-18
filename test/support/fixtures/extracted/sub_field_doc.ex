defmodule GuardedStructTest.Fixtures.SubFieldDoc do
  @moduledoc false
  # Compiled to a beam under test/support so `Code.fetch_docs/1` can read the
  # docs chunk of every module a sub_field generates.
  use GuardedStruct

  guardedstruct do
    field :name, String.t()

    sub_field :transaction, struct(),
      doc: """
      One movement of the seller's balance.
      """ do
      field :id, String.t()

      sub_field :fee, struct(), doc: "The fee taken from one transaction." do
        field :amount, integer()
      end
    end

    sub_field :lines, list(struct()), structs: true, doc: "One line of the order." do
      field :sku, String.t()
    end

    sub_field :plain, struct() do
      field :id, String.t()
    end

    sub_field :internal, struct(), doc: false do
      field :id, String.t()
    end

    sub_field :setter, struct() do
      doc "Set with the setter form inside the block."
      field :id, String.t()
    end

    conditional_field :plan, any() do
      field :plan, String.t(), hint: "preset", derives: "validate(string)"

      sub_field :plan, struct(), doc: "A plan given in detail." do
        field :tier, String.t()
      end
    end
  end
end

defmodule GuardedStructTest.Fixtures.SubFieldDocParent do
  @moduledoc "The parent's own doc."
  # The parent writes its own @moduledoc; guardedstruct and doc: must leave it as it is.
  use GuardedStruct

  guardedstruct do
    sub_field :child, struct(), doc: "The child's **own** doc." do
      field :id, String.t()
    end
  end
end

defmodule GuardedStructTest.Fixtures.SubFieldDocNoParentDoc do
  # No @moduledoc here: guardedstruct must not invent one.
  use GuardedStruct

  guardedstruct do
    field :id, String.t()
  end
end
