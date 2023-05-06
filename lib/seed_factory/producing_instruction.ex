defmodule SeedFactory.ProducingInstruction do
  @moduledoc false
  defstruct [:entity, :from]

  @schema [
    entity: [
      type: :atom,
      required: true,
      doc: "A name of the entity"
    ],
    from: [
      type: :atom,
      required: true,
      doc: "A name of the field returned by resolver"
    ]
  ]

  def schema, do: @schema
end
