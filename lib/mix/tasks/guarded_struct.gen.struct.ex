if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.GuardedStruct.Gen.Struct do
    @example "mix guarded_struct.gen.struct MyApp.User name:string age:integer email:string"
    @shortdoc "Scaffold a starter GuardedStruct module"

    @moduledoc """
    #{@shortdoc}

    ## Example

    ```sh
    #{@example}
    ```

    Generates `lib/my_app/user.ex` with placeholder fields and reasonable
    derive defaults. Use it as a starting point — refine the validations
    and add `enforce: true` / `default:` as needed.

    ## Field syntax

    Each `name:type` argument becomes one `field` line. Supported types:

      * `string` — `String.t()` with `validate(string)`
      * `integer` — `integer()` with `validate(integer)`
      * `float` — `float()` with `validate(float)`
      * `boolean` — `boolean()` with `validate(boolean)`
      * `uuid` — `String.t()` with `validate(uuid)`
      * `email` — `String.t()` with `validate(email_r)`
      * `url` — `String.t()` with `validate(url)`
      * `date` — `String.t()` with `validate(date)`
      * `datetime` — `String.t()` with `validate(datetime)`
      * `map` — `map()` with `validate(map)`
      * `list` — `list()` with `validate(list)`
      * `any` — no derive, type-only

    Append `!` to a field name to mark it `enforce: true`:

        mix guarded_struct.gen.struct MyApp.User name!:string age:integer
    """

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :guarded_struct,
        example: @example,
        positional: [:module_name, fields: [rest: true, optional: true]],
        schema: [],
        defaults: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      module_name = igniter.args.positional.module_name
      field_specs = igniter.args.positional.fields || []

      module = Igniter.Project.Module.parse(module_name)
      file_path = Igniter.Project.Module.proper_location(igniter, module)

      fields_code =
        field_specs
        |> Enum.map(&parse_field_spec/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&render_field/1)
        |> Enum.join("\n    ")

      contents = """
      defmodule #{inspect(module)} do
        use GuardedStruct

        guardedstruct do
          #{fields_code}
        end
      end
      """

      Igniter.create_new_file(igniter, file_path, contents, on_exists: :skip)
    end

    defp parse_field_spec(spec) do
      case String.split(spec, ":", parts: 2) do
        [name_part, type_part] -> {parse_name(name_part), type_part}
        [_only] -> nil
      end
    end

    defp parse_name(name) do
      cond do
        String.ends_with?(name, "!") -> {String.trim_trailing(name, "!"), :enforce}
        true -> {name, :optional}
      end
    end

    defp render_field({{name, enforce_flag}, type}) do
      atom_name = ":#{name}"
      type_ast = type_ast_for(type)
      derive = derive_for(type)
      enforce = if enforce_flag == :enforce, do: ", enforce: true", else: ""
      derive_opt = if derive, do: ~s(, derives: "#{derive}"), else: ""

      "field(#{atom_name}, #{type_ast}#{enforce}#{derive_opt})"
    end

    @type_table %{
      "string" => {"String.t()", "validate(string)"},
      "integer" => {"integer()", "validate(integer)"},
      "float" => {"float()", "validate(float)"},
      "boolean" => {"boolean()", "validate(boolean)"},
      "uuid" => {"String.t()", "validate(uuid)"},
      "email" => {"String.t()", "validate(email_r)"},
      "url" => {"String.t()", "validate(url)"},
      "date" => {"String.t()", "validate(date)"},
      "datetime" => {"String.t()", "validate(datetime)"},
      "map" => {"map()", "validate(map)"},
      "list" => {"list()", "validate(list)"},
      "any" => {"any()", nil}
    }

    defp type_ast_for(type) do
      case Map.get(@type_table, type) do
        {ast, _} -> ast
        nil -> "any()"
      end
    end

    defp derive_for(type) do
      case Map.get(@type_table, type) do
        {_, derive} -> derive
        nil -> nil
      end
    end
  end
else
  defmodule Mix.Tasks.GuardedStruct.Gen.Struct do
    @shortdoc "Scaffold a GuardedStruct module | Install `igniter` to use"
    @moduledoc @shortdoc

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'guarded_struct.gen.struct' requires igniter. Add to your `mix.exs`:

          {:igniter, "~> 0.7", only: [:dev, :test]}

      and run `mix deps.get`.
      """)

      exit({:shutdown, 1})
    end
  end
end
