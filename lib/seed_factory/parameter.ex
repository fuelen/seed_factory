defmodule SeedFactory.Parameter do
  @moduledoc false
  @derive {Inspect, except: [:__spark_metadata__]}

  defstruct [
    :name,
    :params,
    :map,
    :with_traits,
    :value,
    :generate,
    :entity,
    :type,
    __spark_metadata__: nil
  ]

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
    type = detect_type(parameter)

    with :ok <-
           validate(
             is_nil(parameter.with_traits) or type == :entity,
             ":with_traits option can be used only if entity is specified"
           ) do
      parameter =
        parameter
        |> Map.update!(:params, &SeedFactory.Params.index_by_name/1)
        |> Map.put(:type, type)

      {:ok, parameter}
    end
  end

  defp detect_type(parameter) do
    cond do
      not is_nil(parameter.generate) -> :generator
      not is_nil(parameter.entity) -> :entity
      Enum.any?(parameter.params) -> :container
      true -> :value
    end
  end

  defp validate(true, _), do: :ok
  defp validate(false, message), do: {:error, message}
end
