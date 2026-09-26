defmodule SeedFactory.Trait do
  @moduledoc false
  alias SeedFactory.Trait.Value
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

  @placeholder {__MODULE__, :parameter}
  def placeholder, do: @placeholder

  def placeholder_paths(pattern, path \\ []) do
    Enum.flat_map(pattern, fn
      {key, @placeholder} ->
        [path ++ [key]]

      {key, value} when is_map(value) and not is_struct(value) ->
        placeholder_paths(value, path ++ [key])

      _ ->
        []
    end)
  end

  def name({name, _value}), do: name
  def name(name), do: name

  def parameterized?(trait), do: trait.exec_step.value_path != nil

  # References are validated at the API and schema boundaries. The planner
  # only looks up declarations and substitutes a requested value.
  def fetch!(by_name, {name, value}) do
    for trait <- Map.fetch!(by_name, name),
        Value.fits?(trait.exec_step.value_params, value),
        do: bind(trait, value)
  end

  def fetch!(by_name, name), do: Map.fetch!(by_name, name)

  # Returns the references with each value in the shape its command receives,
  # so the value compares equal to the one tracked after the execution.
  def normalize_references!(by_name, references, entity) do
    {references, _values} =
      Enum.map_reduce(references, %{}, fn reference, values ->
        unless is_atom(reference) or
                 (is_tuple(reference) and tuple_size(reference) == 2 and
                    is_atom(elem(reference, 0))) do
          raise ArgumentError,
                "invalid trait reference for entity #{inspect(entity)}: #{inspect(reference)}"
        end

        declarations =
          case Map.fetch(by_name, name(reference)) do
            {:ok, declarations} ->
              declarations

            :error ->
              raise SeedFactory.UnknownTraitError,
                entity: entity,
                trait: name(reference),
                available: Map.keys(by_name)
          end

        # Schema compilation guarantees all declarations agree on parameterization.
        case {parameterized?(hd(declarations)), reference} do
          {true, {name, value}} ->
            value = Value.normalize!(declarations, name, value, entity)

            {{name, value}, Value.put_value!(values, name, value, entity)}

          {false, ref} when is_atom(ref) ->
            {ref, values}

          {true, _} ->
            raise ArgumentError,
                  "trait #{inspect(reference)} of entity #{inspect(entity)} requires a value"

          {false, _} ->
            raise ArgumentError,
                  "trait #{inspect(name(reference))} of entity #{inspect(entity)} does not accept a value"
        end
      end)

    references
  end

  def bind(trait, value) do
    step = trait.exec_step
    pattern = put_in(step.args_pattern, Enum.map(step.value_path, &Access.key!/1), value)
    %{trait | name: {name(trait.name), value}, exec_step: %{step | args_pattern: pattern}}
  end

  def for_reference(trait, {name, value}) when trait.name == name do
    bind(trait, value)
  end

  def for_reference(trait, _reference), do: trait

  def may_remove?(trait, reference) do
    name(reference) in List.wrap(trait.from) or
      (parameterized?(trait) and name(trait.name) == name(reference))
  end

  # A parameterized declaration overwrites its own previous value. The
  # concrete pattern decides addition; the unbound pattern decides whether
  # the command assigns this property at all.
  # Callers settle certain additions before checking removals.
  def removal_firing(trait, reference, args, addition \\ nil) do
    cond do
      name(reference) in List.wrap(trait.from) ->
        firing(trait, args)

      parameterized?(trait) and name(trait.name) == name(reference) ->
        addition = addition || firing(for_reference(trait, reference), args)

        case {firing(trait, args), addition} do
          {:sure, :cannot} -> :sure
          {:cannot, _} -> :cannot
          _ -> :maybe
        end

      true ->
        :cannot
    end
  end

  # A sure firing has found every key on the path to the placeholder.
  def assigned_value(trait, {name, _requested}, args) do
    if trait.name == name and firing(trait, args) == :sure do
      fetch_path(args, trait.exec_step.value_path)
    end
  end

  def assigned_value(_trait, _reference, _args), do: nil

  def apply_changes(current, added, removed) do
    {removed, remaining} =
      Enum.split_with(current, fn reference ->
        name(reference) in removed or
          (reference not in added and
             Enum.any?(added, fn
               {added_name, _} -> name(reference) == added_name
               _ -> false
             end))
      end)

    additions = Enum.reject(added, &(is_tuple(&1) and &1 in remaining))
    {remaining ++ additions, removed}
  end

  # A value the planner does not know yet, such as the instance of an entity
  # the plan still has to produce.
  @unknown {__MODULE__, :unknown}
  def unknown, do: @unknown

  # Whether the declaration fires for `args` that may hold unknown values:
  # `:sure`, `:cannot`, or `:maybe` when the answer depends on an unknown
  # value. An args_match function is opaque, so it runs only on fully known
  # args.
  def firing(%__MODULE__{name: {_name, value}, exec_step: step}, args) do
    case pattern_firing(step.args_pattern, args) do
      :cannot ->
        :cannot

      status ->
        combine_statuses([status, exact_value_firing(value, fetch_path(args, step.value_path))])
    end
  end

  def firing(%__MODULE__{exec_step: exec_step}, args) do
    case exec_step do
      %{args_pattern: pattern} when is_map(pattern) -> pattern_firing(pattern, args)
      %{args_match: nil} -> :sure
      %{args_match: args_match} -> match_firing(args_match, args)
    end
  end

  def pattern_firing(_pattern, args)
      when not is_map(args) and not is_list(args) and not is_nil(args) and args != @unknown,
      do: :cannot

  def pattern_firing(pattern, args) do
    Enum.reduce_while(pattern, :sure, fn {key, value}, accumulated ->
      status =
        case {value, args} do
          {@placeholder, @unknown} ->
            :maybe

          {@placeholder, _} ->
            if match?({:ok, _}, fetch_key(args, key)) do
              :sure
            else
              :cannot
            end

          _ ->
            value_firing(value, fetch_known(args, key))
        end

      case status do
        :cannot -> {:halt, :cannot}
        :maybe -> {:cont, :maybe}
        :sure -> {:cont, accumulated}
      end
    end)
  end

  defp combine_statuses(statuses) do
    cond do
      :cannot in statuses -> :cannot
      :maybe in statuses -> :maybe
      true -> :sure
    end
  end

  defp fetch_path(@unknown, _path), do: :unknown
  defp fetch_path(value, []), do: {:ok, value}

  defp fetch_path(value, [key | rest]) when is_map(value) or is_list(value) do
    case fetch_key(value, key) do
      {:ok, nested} -> fetch_path(nested, rest)
      :error -> :missing
    end
  end

  defp fetch_path(_value, _path), do: :missing

  defp exact_value_firing(_expected, :unknown), do: :maybe
  defp exact_value_firing(_expected, :missing), do: :cannot

  defp exact_value_firing(expected, {:ok, actual}) do
    cond do
      unknown_inside?(actual) -> :maybe
      expected === actual -> :sure
      true -> :cannot
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

  defp fetch_known(args, key) do
    case fetch_key(args, key) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  defp fetch_key(args, key) when is_map(args), do: Map.fetch(args, key)
  defp fetch_key(args, key) when is_list(args), do: Access.fetch(args, key)
  defp fetch_key(_args, _key), do: :error

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
        reference =
          if parameterized?(trait) do
            {:ok, value} = fetch_path(args, trait.exec_step.value_path)
            {trait.name, value}
          else
            trait.name
          end

        {[reference | add], List.wrap(trait.from) ++ remove}
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
  defp deep_equal_maps?(_map1, map2)
       when not is_map(map2) and not is_list(map2) and not is_nil(map2), do: false

  defp deep_equal_maps?(map1, map2) do
    Enum.all?(map1, fn
      {key, @placeholder} ->
        case fetch_key(map2, key) do
          {:ok, _} -> true
          :error -> false
        end

      {key, value} when is_map(value) and not is_struct(value) ->
        deep_equal_maps?(value, fetch_known(map2, key))

      {key, value} ->
        fetch_known(map2, key) == value
    end)
  end
end
