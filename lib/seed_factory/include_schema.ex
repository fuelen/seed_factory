defmodule SeedFactory.IncludeSchema do
  @moduledoc false
  defstruct [:schema_module]

  @schema [
    schema_module: [
      type: :atom,
      required: true,
      doc: "A schema module to be included"
    ]
  ]

  def schema, do: @schema
end
