defmodule SeedFactory.Transformers.IndexTraits do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def after?(module) do
    module in [
      SeedFactory.Transformers.IncludeSchemas,
      SeedFactory.Transformers.IndexCommands,
      SeedFactory.Transformers.IndexEntities
    ]
  end

  def transform(dsl_state) do
    traits_by_entity =
      dsl_state
      |> Transformer.get_persisted(:root)
      |> Enum.filter(&is_struct(&1, SeedFactory.Trait))
      |> Enum.group_by(& &1.entity)

    trait_name_to_entity =
      traits_by_entity
      |> Enum.flat_map(fn {owner_entity, entity_traits} ->
        Enum.map(entity_traits, fn trait -> {trait.name, owner_entity} end)
      end)
      |> Map.new()

    traits =
      traits_by_entity
      |> Map.new(fn {entity, traits} ->
        ensure_known_entity(entity, hd(traits), dsl_state)
        ensure_unique_names(traits, entity)
        ensure_consistent_parameters(traits, entity)
        ensure_traits_have_valid_commands(entity, traits, dsl_state)
        ensure_valid_from_references(entity, traits, trait_name_to_entity)
        ensure_distinct_transitions(traits, entity, dsl_state)
        ensure_no_circular_dependencies(entity, traits)
        traits = traits |> populate_to_field() |> populate_value_params(dsl_state)

        {entity,
         %{
           by_command_name: Enum.group_by(traits, & &1.exec_step.command_name),
           by_name: Enum.group_by(traits, & &1.name)
         }}
      end)

    {:ok, dsl_state |> Transformer.persist(:traits, traits)}
  end

  # The nested params of a container the placeholder sits on decide which
  # values a declaration can receive.
  defp populate_value_params(traits, dsl_state) do
    command_by_name = Transformer.get_persisted(dsl_state, :commands)

    Enum.map(traits, fn
      %{exec_step: %{value_path: nil}} = trait ->
        trait

      %{exec_step: step} = trait ->
        params = Map.fetch!(command_by_name, step.command_name).params

        case placeholder_param(params, step.value_path) do
          %{type: :container, params: nested} ->
            %{trait | exec_step: %{step | value_params: nested}}

          _param ->
            trait
        end
    end)
  end

  defp placeholder_param(params, [key | rest]) do
    case {Map.get(params, key), rest} do
      {%{type: :container, params: nested}, [_ | _]} -> placeholder_param(nested, rest)
      {param, _rest} -> param
    end
  end

  defp populate_to_field(traits) do
    from_to_mapping =
      traits
      |> Enum.flat_map(fn trait -> Enum.map(List.wrap(trait.from), &{&1, trait.name}) end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    Enum.map(traits, fn trait ->
      to = from_to_mapping[trait.name] || []
      %{trait | to: to}
    end)
  end

  defp ensure_consistent_parameters(traits, entity) do
    Enum.each(Enum.group_by(traits, & &1.name), fn {name, declarations} ->
      if name == :as and Enum.any?(declarations, &SeedFactory.Trait.parameterized?/1) do
        raise Spark.Error.DslError,
          path: [:root, :trait, name, entity],
          message: ":as is reserved for entity rebinding and cannot name a parameterized trait",
          location: Spark.Dsl.Entity.anno(hd(declarations))
      end

      if declarations |> Enum.map(&SeedFactory.Trait.parameterized?/1) |> Enum.uniq() |> length() >
           1 do
        raise Spark.Error.DslError,
          path: [:root, :trait, name, entity],
          message: "all declarations of a trait must agree on whether it requires a value",
          location: Spark.Dsl.Entity.anno(hd(declarations))
      end
    end)

    parameterized =
      traits |> Enum.filter(&SeedFactory.Trait.parameterized?/1) |> Enum.map(& &1.name)

    Enum.each(traits, fn trait ->
      if Enum.any?(List.wrap(trait.from), &(&1 in parameterized)) do
        raise Spark.Error.DslError,
          path: [:root, :trait, trait.name, entity],
          message:
            "parameterized traits cannot be used in from; assigning a new value replaces the previous value automatically",
          location: Spark.Dsl.Entity.anno(trait)
      end
    end)
  end

  defp ensure_known_entity(entity, trait, dsl_state) do
    command_name_by_entity = Spark.Dsl.Transformer.get_persisted(dsl_state, :entities)

    if Map.has_key?(command_name_by_entity, entity) do
      :ok
    else
      suggestion =
        SeedFactory.DidYouMean.suggest(entity, Map.keys(command_name_by_entity))

      raise Spark.Error.DslError,
        path: [:root, :trait, trait.name, entity],
        message: "unknown entity#{SeedFactory.DidYouMean.format_suggestion(suggestion)}",
        location: Spark.Dsl.Entity.anno(trait)
    end
  end

  defp ensure_traits_have_valid_commands(entity, traits, dsl_state) do
    command_by_name = Spark.Dsl.Transformer.get_persisted(dsl_state, :commands)

    Enum.each(traits, fn trait ->
      command =
        case Map.fetch(command_by_name, trait.exec_step.command_name) do
          {:ok, command} ->
            command

          :error ->
            suggestion =
              SeedFactory.DidYouMean.suggest(
                trait.exec_step.command_name,
                Map.keys(command_by_name)
              )

            raise Spark.Error.DslError,
              path: [:root, :trait, trait.name, entity],
              message:
                "unknown command #{inspect(trait.exec_step.command_name)}#{SeedFactory.DidYouMean.format_suggestion(suggestion)}",
              location: Spark.Dsl.Entity.anno(trait)
        end

      if trait.from == [] do
        raise Spark.Error.DslError,
          path: [:root, :trait, trait.name, entity],
          message: ":from option cannot be an empty list",
          location: Spark.Dsl.Entity.anno(trait)
      end

      transition? = not is_nil(trait.from)

      if transition? do
        produces_entity? =
          Enum.any?(command.producing_instructions, &(&1.entity == entity))

        updates_entity? =
          Enum.any?(command.updating_instructions, &(&1.entity == entity))

        cond do
          produces_entity? ->
            raise Spark.Error.DslError,
              path: [:root, :trait, trait.name, entity],
              message:
                "trait references #{inspect(command.name)} via `from`, but the command produces the #{inspect(entity)} entity. Transitions must update existing entities.",
              location: Spark.Dsl.Entity.anno(trait)

          not updates_entity? ->
            raise Spark.Error.DslError,
              path: [:root, :trait, trait.name, entity],
              message:
                "trait references #{inspect(command.name)} via `from`, but the command does not update the #{inspect(entity)} entity.",
              location: Spark.Dsl.Entity.anno(trait)

          true ->
            :ok
        end
      end

      instructions = command.producing_instructions ++ command.updating_instructions

      if not Enum.any?(instructions, &(&1.entity == entity)) do
        raise Spark.Error.DslError,
          path: [:root, :trait, trait.name, entity],
          message:
            "contains an exec step to the #{inspect(trait.exec_step.command_name)} command which neither produces nor updates the #{inspect(entity)} entity",
          location: Spark.Dsl.Entity.anno(trait)
      end

      ensure_known_pattern_keys(trait, entity, command)
    end)
  end

  # Keys of a map held by a value, generator or entity param are not declared
  # anywhere, so only params and the nested params of containers are checked.
  defp ensure_known_pattern_keys(trait, entity, command) do
    case unknown_pattern_key(trait.exec_step.args_pattern || %{}, command.params, []) do
      nil ->
        :ok

      {path, params} ->
        suggestion =
          case hd(path) do
            key when is_atom(key) -> SeedFactory.DidYouMean.suggest(key, Map.keys(params))
            _key -> nil
          end

        {key, suggestion} =
          case {path, suggestion} do
            {[key], suggestion} -> {key, suggestion}
            {[_key | _containers], nil} -> {Enum.reverse(path), nil}
            {[_key | containers], name} -> {Enum.reverse(path), Enum.reverse([name | containers])}
          end

        raise Spark.Error.DslError,
          path: [:root, :trait, trait.name, entity],
          message:
            "unknown param #{inspect(key)} in `args_pattern` of the #{inspect(command.name)} command" <>
              SeedFactory.DidYouMean.format_suggestion(suggestion),
          location: Spark.Dsl.Entity.anno(trait)
    end
  end

  defp unknown_pattern_key(pattern, params, path) do
    Enum.find_value(pattern, fn {key, value} ->
      case Map.fetch(params, key) do
        :error ->
          {[key | path], params}

        {:ok, %{type: :container, params: nested_params}}
        when is_map(value) and not is_struct(value) ->
          unknown_pattern_key(value, nested_params, [key | path])

        {:ok, _param} ->
          nil
      end
    end)
  end

  defp ensure_unique_names(traits, entity) do
    traits
    |> Enum.group_by(&{&1.name, &1.exec_step.command_name})
    |> Enum.each(fn
      {_, [_]} ->
        :ok

      {{trait_name, _command_name}, [_first, second | _rest]} ->
        raise Spark.Error.DslError,
          path: [:root, :trait, trait_name, entity],
          message: "duplicated trait",
          location: Spark.Dsl.Entity.anno(second)
    end)
  end

  # Declarations that all constrain their args are accepted: whether two
  # patterns or matchers overlap is undecidable.
  defp ensure_distinct_transitions(traits, entity, dsl_state) do
    command_by_name = Transformer.get_persisted(dsl_state, :commands)

    traits
    |> Enum.reject(&is_nil(&1.from))
    |> Enum.group_by(&{&1.exec_step.command_name, MapSet.new(List.wrap(&1.from))})
    |> Enum.each(fn {{command_name, _from}, declarations} ->
      case Enum.split_with(declarations, &unconditional?(&1, command_by_name)) do
        {[unconditional, another_unconditional | _], _} ->
          raise_shared_transition!(
            entity,
            command_name,
            another_unconditional,
            unconditional,
            "both apply on every run. Did you mean to declare one of them without `from`, " <>
              "as a trait that only adds a property?"
          )

        {[unconditional], [conditional | _]} ->
          raise_shared_transition!(
            entity,
            command_name,
            conditional,
            unconditional,
            "#{inspect(unconditional.name)} applies on every run. " <>
              "Did you mean to declare #{inspect(conditional.name)} without `from`, " <>
              "as a trait that only adds a property, " <>
              "or to constrain #{inspect(unconditional.name)} with a fixed value in `args_pattern`?"
          )

        _ ->
          :ok
      end
    end)
  end

  defp raise_shared_transition!(entity, command_name, trait, unconditional, explanation) do
    raise Spark.Error.DslError,
      path: [:root, :trait, trait.name, entity],
      message:
        "#{inspect(trait.name)} and #{inspect(unconditional.name)} both replace " <>
          "#{inspect(trait.from)} when #{inspect(command_name)} runs, and " <> explanation,
      location: Spark.Dsl.Entity.anno(trait)
  end

  defp unconditional?(trait, command_by_name) do
    params = Map.fetch!(command_by_name, trait.exec_step.command_name).params

    is_nil(trait.exec_step.args_match) and
      always_matches?(trait.exec_step.args_pattern || %{}, params)
  end

  # The args of a run carry every declared param, the nested params of a
  # container included, so a placeholder on one matches on every run. A map
  # held by any other param can miss the key.
  defp always_matches?(pattern, params) do
    placeholder = SeedFactory.Trait.placeholder()

    Enum.all?(pattern, fn {key, value} ->
      case {value, Map.fetch(params, key)} do
        {^placeholder, {:ok, _param}} ->
          true

        {nested, {:ok, %{type: :container, params: nested_params}}}
        when is_map(nested) and not is_struct(nested) ->
          always_matches?(nested, nested_params)

        _other ->
          false
      end
    end)
  end

  defp ensure_no_circular_dependencies(entity, traits) do
    # Every declaration of a name contributes from-edges: a map keyed by name
    # alone would shadow all declarations but the last one.
    traits_by_name = Enum.group_by(traits, & &1.name)

    Enum.reduce(traits, MapSet.new(), fn trait, visited ->
      detect_cycle(trait.name, traits_by_name, MapSet.new(), [], visited, entity)
    end)
  end

  defp detect_cycle(trait_name, traits_by_name, in_path, path_list, visited, entity) do
    cond do
      MapSet.member?(visited, trait_name) ->
        visited

      MapSet.member?(in_path, trait_name) ->
        cycle = build_cycle_path(trait_name, path_list)
        edge_owner = hd(path_list)

        # The name may be declared several times: point at the declaration
        # carrying the edge that closes the cycle, not at the first one.
        trait =
          traits_by_name
          |> Map.fetch!(edge_owner)
          |> Enum.find(&(trait_name in List.wrap(&1.from)))

        raise Spark.Error.DslError,
          path: [:root, :trait, edge_owner, entity],
          message: "circular trait dependency detected: #{cycle}",
          location: Spark.Dsl.Entity.anno(trait)

      true ->
        visited = traverse_from(trait_name, traits_by_name, in_path, path_list, visited, entity)
        MapSet.put(visited, trait_name)
    end
  end

  defp traverse_from(trait_name, traits_by_name, in_path, path_list, visited, entity) do
    traits_by_name
    |> Map.fetch!(trait_name)
    |> Enum.reduce(visited, fn
      %{from: nil}, visited ->
        visited

      %{from: from}, visited ->
        new_in_path = MapSet.put(in_path, trait_name)
        new_path_list = [trait_name | path_list]

        from
        |> List.wrap()
        |> Enum.reduce(visited, fn from_name, visited ->
          detect_cycle(from_name, traits_by_name, new_in_path, new_path_list, visited, entity)
        end)
    end)
  end

  defp build_cycle_path(trait_name, path_list) do
    path_list
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 != trait_name))
    |> Kernel.++([trait_name])
    |> Enum.join(" -> ")
  end

  defp ensure_valid_from_references(entity, traits, trait_name_to_entity) do
    trait_names_for_entity = MapSet.new(traits, & &1.name)

    Enum.each(traits, fn trait ->
      validate_from_references(trait, entity, trait_names_for_entity, trait_name_to_entity)
    end)
  end

  defp validate_from_references(%{from: nil}, _entity, _valid_trait_names, _trait_name_to_entity),
    do: :ok

  defp validate_from_references(
         %{from: from_trait_names} = trait,
         entity,
         valid_trait_names,
         trait_name_to_entity
       )
       when is_list(from_trait_names) do
    Enum.each(from_trait_names, fn from_trait_name ->
      validate_single_from_reference(
        trait,
        entity,
        from_trait_name,
        valid_trait_names,
        trait_name_to_entity
      )
    end)
  end

  defp validate_from_references(
         %{from: from_trait_name} = trait,
         entity,
         valid_trait_names,
         trait_name_to_entity
       ) do
    validate_single_from_reference(
      trait,
      entity,
      from_trait_name,
      valid_trait_names,
      trait_name_to_entity
    )
  end

  defp validate_single_from_reference(
         trait,
         entity,
         from_trait_name,
         valid_trait_names,
         trait_name_to_entity
       ) do
    cond do
      MapSet.member?(valid_trait_names, from_trait_name) ->
        :ok

      Map.has_key?(trait_name_to_entity, from_trait_name) ->
        other_entity = Map.get(trait_name_to_entity, from_trait_name)

        raise Spark.Error.DslError,
          path: [:root, :trait, trait.name, entity],
          message:
            "trait #{inspect(from_trait_name)} in `from` option belongs to entity #{inspect(other_entity)}, not #{inspect(entity)}",
          location: Spark.Dsl.Entity.anno(trait)

      true ->
        suggestion = SeedFactory.DidYouMean.suggest(from_trait_name, valid_trait_names)

        raise Spark.Error.DslError,
          path: [:root, :trait, trait.name, entity],
          message:
            "unknown trait #{inspect(from_trait_name)} in `from` option#{SeedFactory.DidYouMean.format_suggestion(suggestion)}",
          location: Spark.Dsl.Entity.anno(trait)
    end
  end
end
