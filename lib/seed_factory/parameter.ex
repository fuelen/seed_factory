defmodule SeedFactory.Parameter do
  @moduledoc false
  defstruct [:name, :params, :map, :with_traits, :value, :generate, :entity, :type]

  @schema [
    name: [
      type: :atom,
      required: true
    ],
    value: [type: :any],
    generate: [type: {:fun, 0}],
    entity: [type: :atom],
    map: [type: {:fun, 1}],
    with_traits: [type: {:list, :atom}]
  ]

  def schema, do: @schema

  def transform(parameter) do
    type =
      cond do
        not is_nil(parameter.generate) -> :generator
        not is_nil(parameter.entity) -> :entity
        Enum.any?(parameter.params) -> :container
        true -> :value
      end

    parameter =
      parameter
      |> Map.update!(:params, &SeedFactory.Params.index_by_name/1)
      |> Map.put(:type, type)

    {:ok, parameter}
  end
end
