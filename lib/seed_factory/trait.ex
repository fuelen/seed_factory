defmodule SeedFactory.Trait do
  @moduledoc false
  defstruct [
    :name,
    :entity,
    :exec_step,
    :from
  ]

  @schema [
    name: [
      type: :atom,
      required: true,
      doc: "A name of the trait"
    ],
    entity: [
      type: :atom,
      required: true,
      doc: "A name of the entity"
    ],
    from: [
      type: :atom,
      doc: "A name of the trait that should be replaced by the new one"
    ]
  ]

  def schema, do: @schema
end
