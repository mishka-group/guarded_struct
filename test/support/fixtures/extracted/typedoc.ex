defmodule GuardedStructTest.Fixtures.TypedocAddress do
  @moduledoc "A postal address."
  # A struct: target of the fixtures below.
  use GuardedStruct

  guardedstruct do
    field :city, String.t(), enforce: true, doc: "The city."
  end
end

defmodule GuardedStructTest.Fixtures.TypedocParent do
  @moduledoc "The parent's own doc."
  # Every kind of field, so the generated types and the field table can be read back.
  use GuardedStruct

  alias GuardedStructTest.Fixtures.TypedocAddress

  guardedstruct do
    field :name, String.t(),
      enforce: true,
      derives: "sanitize(trim) validate(string)",
      doc: "The name; a | pipe stays in its cell."

    field :address, struct(), struct: TypedocAddress, doc: "Where the parent lives."
    field :addresses, list(struct()), structs: TypedocAddress
    field :kept, TypedocAddress.t(), struct: TypedocAddress
    field :count, integer(), default: 0, validator: {__MODULE__, :check}
    field :secret, String.t(), doc: false

    sub_field :profile, struct(),
      doc: """
      The profile of the parent.

      A second paragraph that stays on the profile page.
      """ do
      field :bio, String.t(), doc: "A short bio."
    end

    sub_field :lines, list(struct()), structs: true, doc: "One line." do
      field :sku, String.t()
    end

    sub_field :internal, struct(), doc: false do
      field :id, String.t()
    end

    conditional_field :plan, any(), doc: "A plan by name or in detail." do
      field :plan, String.t(), derives: "validate(string)"

      sub_field :plan, struct() do
        field :tier, String.t()
      end

      field :plan, struct(), struct: TypedocAddress
    end

    virtual_field :confirm, String.t(), doc: "Checked, then dropped."
    dynamic_field :meta, doc: "Free-form data."
  end

  def check(_field, value), do: {:ok, value}
end

defmodule GuardedStructTest.Fixtures.TypedocOwnTypedoc do
  @moduledoc "Has its own typedoc."
  use GuardedStruct

  @typedoc "My own words about t."
  guardedstruct do
    field :id, String.t()
  end
end

defmodule GuardedStructTest.Fixtures.TypedocPattern do
  @moduledoc "A map keyed by pattern."
  use GuardedStruct

  guardedstruct do
    field ~r/^env_/, String.t(), doc: "An environment value."
  end
end

defmodule GuardedStructTest.Fixtures.TypedocUses do
  @moduledoc "Uses its own modules for block-less sub_fields."
  # Address is nested here; Items lives in typedoc_own_modules.ex, so the compiler waits for it.
  use GuardedStruct

  defmodule Address do
    @moduledoc "The user's own address module."
    use GuardedStruct

    guardedstruct do
      field :city, String.t(), enforce: true
    end
  end

  guardedstruct do
    sub_field :address, struct(), doc: "Where it is."
    sub_field :items, list(struct()), structs: true
  end
end
