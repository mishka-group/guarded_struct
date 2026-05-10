if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.GuardedStruct.Install do
    @example "mix igniter.install guarded_struct"
    @shortdoc "One-command project setup for guarded_struct"

    @moduledoc """
    #{@shortdoc}

    ## Example

    ```sh
    #{@example}
    ```

    ## What it does

      1. Adds `{:guarded_struct, "~> 0.1.0"}` to `mix.exs` deps (if not already)
      2. Registers a `lint` alias chaining `mix spark.formatter` then `mix format`
      3. Seeds `config :guarded_struct, derive_extensions: []` in `config/config.exs`
         so users have an obvious place to plug in custom validators

    ## Options

      * `--strict` — also set `config :guarded_struct, strict_derive_ops: true`
        to catch typos in derive op names at compile time
      * `--strict-paths` — also set `config :guarded_struct, strict_core_key_paths: true`
        to verify `from:`/`on:` paths reference real fields
    """

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :guarded_struct,
        example: @example,
        positional: [],
        schema: [strict: :boolean, strict_paths: :boolean],
        defaults: [strict: false, strict_paths: false]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      strict? = igniter.args.options[:strict]
      strict_paths? = igniter.args.options[:strict_paths]

      igniter
      |> Igniter.Project.TaskAliases.add_alias("lint", ["spark.formatter", "format"])
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :guarded_struct,
        [:derive_extensions],
        []
      )
      |> maybe_set_strict(strict?)
      |> maybe_set_strict_paths(strict_paths?)
      |> Igniter.add_notice("""
      guarded_struct installed.

      Quick start — add to any module:

          defmodule MyApp.User do
            use GuardedStruct

            guardedstruct do
              field :name, String.t(), enforce: true,
                derives: "sanitize(trim) validate(string, max_len=80)"
              field :email, String.t(), enforce: true,
                derives: "validate(email_r)"
            end
          end

      Then call MyApp.User.builder(%{name: "Alice", email: "alice@example.com"}).
      See https://hexdocs.pm/guarded_struct for the full guide.
      """)
    end

    defp maybe_set_strict(igniter, false), do: igniter

    defp maybe_set_strict(igniter, true) do
      Igniter.Project.Config.configure_new(
        igniter,
        "config.exs",
        :guarded_struct,
        [:strict_derive_ops],
        true
      )
    end

    defp maybe_set_strict_paths(igniter, false), do: igniter

    defp maybe_set_strict_paths(igniter, true) do
      Igniter.Project.Config.configure_new(
        igniter,
        "config.exs",
        :guarded_struct,
        [:strict_core_key_paths],
        true
      )
    end
  end
else
  defmodule Mix.Tasks.GuardedStruct.Install do
    @shortdoc "One-command project setup for guarded_struct | Install `igniter` to use"
    @moduledoc @shortdoc

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'guarded_struct.install' requires igniter. Add to your `mix.exs`:

          {:igniter, "~> 0.7", only: [:dev, :test]}

      and run `mix deps.get`.
      """)

      exit({:shutdown, 1})
    end
  end
end
