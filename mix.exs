defmodule GuardedStruct.MixProject do
  use Mix.Project

  @version "0.0.5"
  @source_url "https://github.com/mishka-group/guarded_struct"

  def project do
    [
      app: :guarded_struct,
      version: @version,
      elixir: "~> 1.17",
      name: "GuardedStruct",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: description(),
      package: package(),
      source_url: @source_url,
      docs: [
        main: "readme",
        source_ref: "v#{@version}",
        extras: ["README.md", "CHANGELOG.md"],
        source_url: @source_url
      ]
    ]
  end

  defp aliases do
    [
      "spark.formatter":
        "spark.formatter --extensions GuardedStruct.Dsl,GuardedStruct.AshResource",
      "spark.cheat_sheets":
        "spark.cheat_sheets --extensions GuardedStruct.Dsl,GuardedStruct.AshResource",
      lint: ["spark.formatter", "format"]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description() do
    "GuardedStruct macro allows to build Structs that provide you with a number of important options Validation, Sanitizing, Constructor"
  end

  defp package() do
    [
      files: ~w(lib .formatter.exs mix.exs LICENSE README*),
      licenses: ["Apache-2.0"],
      maintainers: ["Shahryar Tavakkoli"],
      links: %{
        "Mishka" => "https://mishka.tools",
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md",
        "LiveBook document" => "#{@source_url}/blob/master/guidance/guarded-struct.livemd"
      }
    ]
  end

  defp deps do
    [
      # necessary
      {:spark, "~> 2.7"},
      {:splode, "~> 0.3"},
      {:html_sanitize_ex, "~> 1.5"},
      # required by Spark.Formatter for `mix format` and `mix spark.formatter`
      {:sourceror, "~> 1.7", only: [:dev, :test]},
      # document
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false},

      # test env
      {:email_checker, "~> 0.2.4", optional: true, only: :test},
      {:ex_url, "~> 2.0.2", optional: true, only: :test},
      {:ex_phone_number, "~> 0.4.11", optional: true, only: :test},
      {:sweet_xml,
       github: "kbrw/sweet_xml", branch: "master", override: true, optional: true, only: :test},
      {:igniter,
       path: "/Users/shahryar/Documents/Programming/Elixir/igniter",
       only: [:dev, :test],
       override: true}
    ]
  end
end
