defmodule SeedFactory.IncludeSchema do
  @moduledoc false
  @derive {Inspect, except: [:__spark_metadata__]}

  defstruct [:schema_module, __spark_metadata__: nil]

  @schema [
    schema_module: [
      type: :atom,
      required: true,
      doc: "A schema module to be included"
    ]
  ]

  def schema, do: @schema
end
