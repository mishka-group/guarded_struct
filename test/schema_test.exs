defmodule GuardedStructTest.SchemaTest do
  use ExUnit.Case, async: true

  alias GuardedStruct.Schema

  defmodule Person do
    use GuardedStruct

    guardedstruct do
      field(:name, String.t(),
        enforce: true,
        derives: "validate(string, max_len=80, min_len=1)"
      )

      field(:age, integer(), derives: "validate(integer, max_len=120, min_len=0)")
      field(:email, String.t(), derives: "validate(email_r)")
      field(:role, String.t(), derives: "validate(enum=String[admin::user::guest])")
      field(:website, String.t(), derives: "validate(url)")
      field(:user_id, String.t(), derives: "validate(uuid)")
      field(:active, boolean(), default: true, derives: "validate(boolean)")
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

  describe "openapi/1" do
    test "wraps json_schema in OpenAPI 3.1 envelope" do
      doc = Schema.openapi(Person)

      assert doc["openapi"] == "3.1.0"
      assert is_map(doc["info"])
      assert is_map(doc["components"]["schemas"])
    end

    test "schema name is the inspected module with dots replaced" do
      doc = Schema.openapi(Person)

      assert Map.has_key?(
               doc["components"]["schemas"],
               "GuardedStructTest_SchemaTest_Person"
             )
    end

    test "envelope strips $schema and title from inner schemas" do
      doc = Schema.openapi(Person)
      [schema] = doc["components"]["schemas"] |> Map.values()

      refute Map.has_key?(schema, "$schema")
      refute Map.has_key?(schema, "title")
      assert schema["type"] == "object"
    end

    test "passing a list bundles multiple schemas" do
      defmodule Other do
        use GuardedStruct

        guardedstruct do
          field(:x, integer())
        end
      end

      doc = Schema.openapi([Person, Other])
      assert map_size(doc["components"]["schemas"]) == 2
    end

    test "single module is treated as list-of-one" do
      single = Schema.openapi(Person)
      list = Schema.openapi([Person])

      assert single["components"] == list["components"]
    end
  end
end
