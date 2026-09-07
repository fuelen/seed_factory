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

  # A value the planner does not know yet, such as the instance of an entity
  # the plan still has to produce.
  @unknown {__MODULE__, :unknown}
  def unknown, do: @unknown

  # Whether the declaration fires for `args` that may hold unknown values:
  # `:sure`, `:cannot`, or `:maybe` when the answer depends on an unknown
  # value. An args_match function is opaque, so it runs only on fully known
  # args.
  def firing(%__MODULE__{exec_step: exec_step}, args) do
    case exec_step do
      %{args_pattern: pattern} when is_map(pattern) -> pattern_firing(pattern, args)
      %{args_match: nil} -> :sure
      %{args_match: args_match} -> match_firing(args_match, args)
    end
  end

  def pattern_firing(pattern, args) do
    statuses = for {key, value} <- pattern, do: value_firing(value, fetch_known(args, key))

    cond do
      :cannot in statuses -> :cannot
      :maybe in statuses -> :maybe
      true -> :sure
    end
  end

  defp value_firing(value, actual) when is_map(value) and not is_struct(value) do
    pattern_firing(value, actual)
  end

  defp value_firing(_value, @unknown), do: :maybe

  defp value_firing(value, actual) do
    if value == actual do
      :sure
    else
      :cannot
    end
  end

  # The same Access read as deep_equal_maps?, keyword lists and nil included.
  defp fetch_known(@unknown, _key), do: @unknown
  defp fetch_known(args, key), do: args[key]

  defp match_firing(args_match, args) do
    cond do
      unknown_inside?(args) -> :maybe
      args_match.(args) -> :sure
      true -> :cannot
    end
  end

  defp unknown_inside?(@unknown), do: true

  defp unknown_inside?(value) when is_map(value) and not is_struct(value) do
    Enum.any?(value, fn {_key, nested} -> unknown_inside?(nested) end)
  end

  defp unknown_inside?(_value), do: false

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
