defmodule GuardedStructTest.SchemaTest do
  use ExUnit.Case, async: true

  alias GuardedStruct.Schema

  defmodule Person do
    use GuardedStruct

    guardedstruct do
      field(:name, String.t(),
        enforce: true,
        derive: "validate(string, max_len=80, min_len=1)"
      )

      field(:age, integer(), derive: "validate(integer, max_len=120, min_len=0)")
      field(:email, String.t(), derive: "validate(email_r)")
      field(:role, String.t(), derive: "validate(enum=String[admin::user::guest])")
      field(:website, String.t(), derive: "validate(url)")
      field(:user_id, String.t(), derive: "validate(uuid)")
      field(:active, boolean(), default: true, derive: "validate(boolean)")
    end
  end

  test "json_schema includes top-level properties + required" do
    s = Schema.json_schema(Person)

    assert s["type"] == "object"
    assert s["$schema"] =~ "json-schema.org"
    assert "name" in s["required"]
    assert is_map(s["properties"])
  end

  test "string field with max_len/min_len gets maxLength/minLength" do
    s = Schema.json_schema(Person)
    name = s["properties"]["name"]

    assert name["type"] == "string"
    assert name["maxLength"] == 80
    assert name["minLength"] == 1
  end

  test "integer field with max_len/min_len gets maximum/minimum" do
    s = Schema.json_schema(Person)
    age = s["properties"]["age"]

    assert age["type"] == "integer"
    assert age["maximum"] == 120
    assert age["minimum"] == 0
  end

  test "uuid/url/email/datetime become JSON-Schema formats" do
    s = Schema.json_schema(Person)
    assert s["properties"]["user_id"]["format"] == "uuid"
    assert s["properties"]["website"]["format"] == "uri"
    assert s["properties"]["email"]["format"] == "email"
  end

  test "enum=String[...] becomes a JSON Schema enum" do
    s = Schema.json_schema(Person)
    role = s["properties"]["role"]
    assert role["enum"] == ["admin", "user", "guest"]
  end

  test "default value is included" do
    s = Schema.json_schema(Person)
    assert s["properties"]["active"]["default"] == true
  end

  test "typescript output is a syntactically reasonable interface" do
    ts = Schema.typescript(Person)

    assert ts =~ "export interface"
    assert ts =~ "name: string;"
    # Optional fields end with `?:`
    assert ts =~ "age?: number;"
    # enum becomes a TS union
    assert ts =~ "role?: \"admin\" | \"user\" | \"guest\";"
  end
end
