if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.GuardedStruct.Gen.Schema do
    @example "mix guarded_struct.gen.schema MyApp.MyStruct --format=json --out=priv/schema.json"
    @shortdoc "Emit a JSON Schema or TypeScript interface for a GuardedStruct module"

    @moduledoc """
    #{@shortdoc}

    ## Example

    ```sh
    #{@example}
    ```

    ## Positional arguments

      * `module` — fully-qualified GuardedStruct module name (e.g. `MyApp.MyStruct`)

    ## Options

      * `--format` / `-f` — `json` (default) or `typescript`
      * `--out` / `-o` — write to a file; if omitted, the rendered schema is
        added as a notice and printed.
    """

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :guarded_struct,
        example: @example,
        positional: [:module],
        schema: [format: :string, out: :string],
        aliases: [f: :format, o: :out],
        defaults: [format: "json"]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      module_str = igniter.args.positional.module
      format = igniter.args.options[:format]
      out = igniter.args.options[:out]

      module = parse_module(module_str)

      cond do
        format not in ["json", "typescript"] ->
          Igniter.add_issue(
            igniter,
            "Unknown format #{inspect(format)}. Use `--format=json` or `--format=typescript`."
          )

        not Code.ensure_loaded?(module) ->
          Igniter.add_issue(
            igniter,
            "Module #{inspect(module)} is not loaded. Did you `mix compile` first, or is the module name correct?"
          )

        not function_exported?(module, :__fields__, 0) ->
          Igniter.add_issue(
            igniter,
            "Module #{inspect(module)} doesn't appear to be a GuardedStruct (no `__fields__/0`)."
          )

        true ->
          render_and_emit(igniter, module, format, out)
      end
    end

    defp parse_module(module_str) do
      cond do
        String.starts_with?(module_str, "Elixir.") -> String.to_atom(module_str)
        true -> String.to_atom("Elixir." <> module_str)
      end
    end

    defp render_and_emit(igniter, module, "json", out) do
      schema = GuardedStruct.Schema.json_schema(module)
      content = encode_json(schema)
      emit(igniter, content, out, default_path(module, "json"))
    end

    defp render_and_emit(igniter, module, "typescript", out) do
      content = GuardedStruct.Schema.typescript(module)
      emit(igniter, content, out, default_path(module, "ts"))
    end

    defp emit(igniter, content, nil, default_path) do
      Igniter.add_notice(
        igniter,
        "Rendered schema (#{default_path} would be the default output path):\n\n#{content}"
      )
    end

    defp emit(igniter, content, path, _default_path) do
      Igniter.create_new_file(igniter, path, content, on_exists: :overwrite)
    end

    defp default_path(module, ext) do
      base = module |> inspect() |> String.replace(".", "_") |> Macro.underscore()
      "priv/schemas/#{base}.#{ext}"
    end

    defp encode_json(value) do
      cond do
        Code.ensure_loaded?(Jason) ->
          Jason.encode!(value, pretty: true)

        Code.ensure_loaded?(:json) and function_exported?(:json, :encode, 1) ->
          value |> :json.encode() |> :unicode.characters_to_binary()

        true ->
          inspect(value, pretty: true, limit: :infinity)
      end
    end
  end
else
  defmodule Mix.Tasks.GuardedStruct.Gen.Schema do
    @shortdoc "Emit a JSON Schema or TypeScript interface for a GuardedStruct module | Install `igniter` to use"
    @moduledoc @shortdoc

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'guarded_struct.gen.schema' requires igniter. Please add to your `mix.exs`:

          {:igniter, "~> 0.7", only: [:dev, :test]}

      and run `mix deps.get`. For more information, see:
      https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
