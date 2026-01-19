defmodule SeedFactory.DeletingInstruction do
  @moduledoc false
  @derive {Inspect, except: [:__spark_metadata__]}

  defstruct [:entity, __spark_metadata__: nil]

  @schema [
    entity: [
      type: :atom,
      required: true,
      doc: "A name of the entity"
    ]
  ]

  def schema, do: @schema
end
