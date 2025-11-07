defmodule SeedFactory.Trait do
  @moduledoc false
  @derive {Inspect, optional: [:from, :to]}

  defstruct [
    :name,
    :entity,
    :exec_step,
    :from,
    to: [],
    __spark_metadata__: nil
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
      type: {:or, [:atom, {:list, :atom}]},
      doc: "A name of the trait or list of the traits that should be replaced by the new trait"
    ]
  ]

  def schema, do: @schema
end
