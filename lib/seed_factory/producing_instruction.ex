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
      doc: "A name of the field returned by resolver"
    ]
  ]

  def schema, do: @schema

  def transform(instruction) do
    case instruction.from do
      nil -> {:ok, %{instruction | from: instruction.entity}}
      _from -> {:ok, instruction}
    end
  end
end
