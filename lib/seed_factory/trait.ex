defmodule SeedFactory.Trait do
  @moduledoc false
  @derive {Inspect, optional: [:from, :to], except: [:__spark_metadata__]}

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

  defp args_match?(%__MODULE__{exec_step: exec_step} = _trait, args) do
    callback = exec_step.args_match || args_pattern_to_args_match_fn(exec_step.args_pattern)
    callback.(args)
  end

  def resolve_changes(possible_traits, args) do
    Enum.reduce(possible_traits, {[], []}, fn trait, {add, remove} = acc ->
      if args_match?(trait, args) do
        {[trait.name | add], List.wrap(trait.from) ++ remove}
      else
        acc
      end
    end)
  end

  defp args_pattern_to_args_match_fn(args_pattern) do
    case args_pattern do
      nil -> fn _ -> true end
      args_pattern -> &deep_equal_maps?(args_pattern, &1)
    end
  end

  # checks whether all values from map1 are present in map2.
  defp deep_equal_maps?(map1, map2) do
    Enum.all?(map1, fn
      {key, value} when is_map(value) and not is_struct(value) ->
        deep_equal_maps?(value, map2[key])

      {key, value} ->
        map2[key] == value
    end)
  end
end
