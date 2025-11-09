defmodule SeedFactory.Params do
  @moduledoc false

  def index_by_name(list) do
    Map.new(list, &{&1.name, &1})
  end

  def prepare_args(params, initial_input, fetch_entity_fn) do
    initial_input = Map.new(initial_input)

    ensure_args_match_defined_params!(initial_input, params)

    Map.new(params, fn
      {key, parameter} ->
        value =
          case parameter.type do
            :generator ->
              Map.get_lazy(initial_input, key, parameter.generate)

            :container ->
              prepare_args(parameter.params, Map.get(initial_input, key, %{}), fetch_entity_fn)

            :entity ->
              case Map.fetch(initial_input, key) do
                {:ok, value} ->
                  value

                :error ->
                  entity = fetch_entity_fn.(parameter.entity)
                  maybe_map(entity, parameter.map)
              end

            :value ->
              Map.get(initial_input, key, parameter.value)
          end

        {key, value}
    end)
  end

  defp ensure_args_match_defined_params!(input, _params) when map_size(input) == 0, do: :noop

  defp ensure_args_match_defined_params!(input, params) do
    case Map.keys(input) -- Map.keys(params) do
      [] ->
        :noop

      keys ->
        raise ArgumentError,
              "Input doesn't match defined params. Redundant keys found: #{inspect(keys)}"
    end
  end

  defp maybe_map(value, map) do
    if map do
      map.(value)
    else
      value
    end
  end
end
