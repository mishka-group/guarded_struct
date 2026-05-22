defmodule GuardedStruct.MixProject do
  use Mix.Project

  @version "0.1.0-beta.4"
  @source_url "https://github.com/mishka-group/guarded_struct"

  def project do
    [
      app: :guarded_struct,
      version: @version,
      elixir: "~> 1.17",
      name: "GuardedStruct",
      elixirc_paths: elixirc_paths(Mix.env()),
      consolidate_protocols: Mix.env() != :test,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: description(),
      package: package(),
      source_url: @source_url,
      docs: docs()
    ]
  end

  # Spark mix tasks require `--extensions` as a CLI flag (no config-file
  # path for it). We pin the list ONCE here so both spark.formatter and
  # spark.cheat_sheets pick it up automatically — and so a short alias
  # like `mix lint` / `mix cheat` works.
  @spark_extensions "GuardedStruct.Dsl,GuardedStruct.AshResource,GuardedStruct.Derive.Extension.Dsl"

  defp aliases do
    [
      "spark.formatter": "spark.formatter --extensions #{@spark_extensions}",
      "spark.cheat_sheets": "spark.cheat_sheets --extensions #{@spark_extensions}",
      lint: ["spark.formatter", "format"],
      cheat: ["spark.cheat_sheets"]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description() do
    "Build Elixir structs with validation, sanitization, nested sub-structs, " <>
      "conditional fields, pattern-keyed maps, and an Ash extension. " <>
      "Built on Spark."
  end

  defp package() do
    [
      files:
        ~w(lib .formatter.exs mix.exs LICENSE README* CHANGELOG* SECURITY* usage-rules.md usage-rules guidance/guarded-struct.livemd .claude/skills),
      licenses: ["Apache-2.0"],
      maintainers: ["Shahryar Tavakkoli"],
      links: %{
        "Mishka" => "https://mishka.tools",
        "GitHub" => @source_url,
        "LiveBook document" => "#{@source_url}/blob/master/guidance/guarded-struct.livemd",
        "Sponsor" => "https://github.com/sponsors/mishka-group",
        "Security policy" => "#{@source_url}/blob/master/SECURITY.md",
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "CHANGELOG.md",
        "SECURITY.md",
        "LICENSE",
        "guidance/guarded-struct.livemd",
        "usage-rules.md",
        "usage-rules/dsl.md",
        "usage-rules/derive.md",
        "usage-rules/conditional.md",
        "usage-rules/validators.md",
        "usage-rules/core-keys.md",
        "usage-rules/extensions.md",
        "usage-rules/ash.md",
        "usage-rules/api.md",
        "usage-rules/errors.md",
        "documentation/dsls/DSL-GuardedStruct.md",
        "documentation/dsls/DSL-GuardedStruct.AshResource.md",
        "documentation/dsls/DSL-GuardedStruct.Derive.Extension.md"
      ],
      groups_for_extras: [
        Guidance: ~r"^guidance/.*",
        "Agent Usage Rules": ~r"^usage-rules.*",
        "DSL Reference": ~r"^documentation/dsls/.*"
      ],
      groups_for_modules: [
        Core: [GuardedStruct, GuardedStruct.Info],
        Validation: [GuardedStruct.Validate],
        "Errors (Splode)": [
          GuardedStruct.Errors,
          GuardedStruct.Errors.Validation,
          GuardedStruct.Errors.Invalid,
          GuardedStruct.Errors.Unknown
        ],
        Extensions: [
          GuardedStruct.Derive.Extension,
          GuardedStruct.AshResource,
          GuardedStruct.AshResource.Info
        ],
        i18n: [GuardedStruct.Messages]
      ],
      nest_modules_by_prefix: [
        GuardedStruct.Errors,
        GuardedStruct.Derive,
        GuardedStruct.Dsl,
        GuardedStruct.Transformers,
        GuardedStruct.Verifiers
      ]
    ]
  end

  defp deps do
    [
      # necessary
      {:spark, "~> 2.7"},
      {:splode, "~> 0.3"},
      {:telemetry, "~> 1.0"},
      {:html_sanitize_ex, "~> 1.5"},
      # required by Spark.Formatter for `mix format` and `mix spark.formatter`
      {:sourceror, "~> 1.7", only: [:dev, :test]},
      # document
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false},

      # property-based testing
      {:stream_data, "~> 1.1", only: [:dev, :test]},

      # tested when jason: true is opted into; the lib itself doesn't depend
      # on Jason — Code.ensure_loaded?(Jason.Encoder) gates the @derive.
      {:jason, "~> 1.4", only: [:dev, :test]},

      # test env
      {:email_checker, "~> 0.2.4", optional: true, only: :test},
      {:ex_url, "~> 2.0.2", optional: true, only: :test},
      {:ex_phone_number, "~> 0.4.11", optional: true, only: :test},
      {:sweet_xml,
       github: "kbrw/sweet_xml", branch: "master", override: true, optional: true, only: :test},
      {:igniter, "~> 0.8.0", only: [:dev, :test]},
      {:ash, "~> 3.0", only: [:dev, :test]}
    ]
  end
end
