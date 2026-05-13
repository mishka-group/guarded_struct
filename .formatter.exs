spark_locals_without_parens = [
  authorized_fields: 1,
  auto: 1,
  conditional_field: 2,
  conditional_field: 3,
  default: 1,
  derive: 1,
  derives: 1,
  domain: 1,
  dynamic_field: 1,
  dynamic_field: 2,
  enforce: 1,
  error: 1,
  field: 2,
  field: 3,
  from: 1,
  hint: 1,
  json: 1,
  main_validator: 1,
  module: 1,
  on: 1,
  opaque: 1,
  priority: 1,
  sanitize_derive: 1,
  struct: 1,
  structs: 1,
  sub_field: 2,
  sub_field: 3,
  type: 1,
  validate_derive: 1,
  validator: 1,
  virtual_field: 2,
  virtual_field: 3
]

[
  import_deps: [:spark],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  plugins: [Spark.Formatter],
  locals_without_parens: spark_locals_without_parens,
  export: [
    locals_without_parens: spark_locals_without_parens
  ]
]
