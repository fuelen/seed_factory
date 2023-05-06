defmodule SeedFactory.DeletingInstruction do
  @moduledoc false
  defstruct [:entity]

  @schema [
    entity: [
      type: :atom,
      required: true,
      doc: "A name of the entity"
    ]
  ]

  def schema, do: @schema
end
