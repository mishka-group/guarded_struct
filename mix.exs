defmodule GuardedStruct.MixProject do
  use Mix.Project

  @version "0.0.1"
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
      description: description(),
      package: package(),
      homepage_url: "https://github.com/mishka-group",
      source_url: @source_url,
      docs: [
        main: "readme",
        source_ref: "v#{@version}",
        extras: ["README.md", "CHANGELOG.md"],
        source_url: @source_url
      ]
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
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md"
      }
    ]
  end

  defp deps do
    [
      {:html_sanitize_ex, "~> 1.4.3", optional: true},
      {:email_checker, "~> 0.2.4", optional: true},
      {:ex_url, "~> 2.0", optional: true},
      {:ex_phone_number, "~> 0.4.5", optional: true},
      {:sweet_xml, github: "kbrw/sweet_xml", branch: "master", override: true, optional: true},
      {:ex_doc, "~> 0.34.2", only: :dev, runtime: false}
    ]
  end
end
