# Used by "mix format"
locals_without_parens = [produce: 2, update: 2, delete: 1, produce: 1, param: 2, param: 3]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
