defmodule GuardedStructTest.Fixtures.AsyncCompile.SimpleParent do
  @moduledoc false
  use GuardedStruct

  guardedstruct do
    field :id, String.t(), enforce: true

    sub_field :profile, struct() do
      field :nickname, String.t()
      field :bio, String.t()
    end
  end
end

defmodule GuardedStructTest.Fixtures.AsyncCompile.WideParent do
  @moduledoc false
  use GuardedStruct

  guardedstruct do
    sub_field :a, struct() do
      field :x, String.t()
    end

    sub_field :b, struct() do
      field :x, String.t()
    end

    sub_field :c, struct() do
      field :x, String.t()
    end

    sub_field :d, struct() do
      field :x, String.t()
    end
  end
end

defmodule GuardedStructTest.Fixtures.AsyncCompile.DeepParent do
  @moduledoc false
  use GuardedStruct

  guardedstruct do
    sub_field :level1, struct() do
      field :tag, String.t()

      sub_field :level2, struct() do
        field :tag, String.t()

        sub_field :level3, struct() do
          field :tag, String.t()

          sub_field :level4, struct() do
            field :value, String.t(), enforce: true
          end
        end
      end
    end
  end
end

defmodule GuardedStructTest.Fixtures.AsyncCompile.WithConditional.V do
  @moduledoc false
  def validate_string(field, value) when is_binary(value), do: {:ok, field, value}
  def validate_string(field, _), do: {:error, field, "not a string"}

  def validate_map(field, value) when is_map(value) and not is_struct(value),
    do: {:ok, field, value}

  def validate_map(field, _), do: {:error, field, "not a map"}
end

defmodule GuardedStructTest.Fixtures.AsyncCompile.WithConditional do
  @moduledoc false
  use GuardedStruct

  alias GuardedStructTest.Fixtures.AsyncCompile.WithConditional.V

  guardedstruct do
    conditional_field :payload, any() do
      field :payload, String.t(), hint: "string", validator: {V, :validate_string}

      sub_field :payload, struct(), hint: "map_form", validator: {V, :validate_map} do
        field :kind, String.t(), enforce: true
      end
    end
  end
end

defmodule GuardedStructTest.Fixtures.AsyncCompile.OrderedDeep do
  @moduledoc false
  use GuardedStruct

  guardedstruct do
    sub_field :nested, struct() do
      field :label, String.t(), default: "child-default"
    end
  end
end
