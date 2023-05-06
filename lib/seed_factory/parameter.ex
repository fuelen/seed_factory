defmodule SeedFactory.Parameter do
  @moduledoc false
  defstruct [:name, :source, :params, :map]

  @schema [
    name: [
      type: :atom,
      required: true
    ],
    source: [
      type: {:or, [:atom, {:fun, 0}]}
    ],
    map: [type: {:fun, 1}]
  ]

  def schema, do: @schema

  def transform(parameter) do
    parameter = Map.update!(parameter, :params, &SeedFactory.Params.index_by_name/1)
    {:ok, parameter}
  end
end
