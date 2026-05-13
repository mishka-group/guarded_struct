import Config

# Spark formatter configuration. `remove_parens?: true` tells the
# `Spark.Formatter` plugin to strip parens from any function call listed
# in `locals_without_parens` (ours + Ash's, via `import_deps: [:spark, :ash]`
# in `.formatter.exs`). Section order keeps DSL blocks in a predictable
# top-down shape inside `mix format`.
config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :authentication,
        :tokens,
        :postgres,
        :json_api,
        :graphql,
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [
      section_order: [
        :json_api,
        :graphql,
        :resources,
        :policies,
        :authorization,
        :domain,
        :execution
      ]
    ]
  ]
