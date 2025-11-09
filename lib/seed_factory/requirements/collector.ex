defmodule SeedFactory.Requirements.Collector do
  @moduledoc false

  def resolve_traits(
        {requirements, command_names} = acc,
        traits,
        traits_by_name,
        trail_map,
        required_by
      ) do
    with {:ok, filtered_traits} <- filter_rejected_commands(traits, requirements) do
      case check_already_executed(filtered_traits, trail_map, acc) do
        {:already_executed, result} ->
          result

        {:trait_mismatch, trait, added} ->
          {:error, {:trait_mismatch, trait, added, required_by}}

        :continue ->
          {graph, updated_command_names} =
            SeedFactory.Requirements.CommandGraph.register_commands(
              requirements.graph,
              Enum.map(filtered_traits, & &1.exec_step.command_name),
              required_by,
              filtered_traits
            )

          updated_requirements = %{requirements | graph: graph}
          updated_acc = {updated_requirements, MapSet.union(command_names, updated_command_names)}

          case resolve_trait_dependencies(
                 filtered_traits,
                 updated_acc,
                 traits_by_name,
                 trail_map,
                 required_by
               ) do
            {:ok, final_acc, _resolved_traits} ->
              {:ok, final_acc}

            {:partial, final_acc, _resolved_traits, _errors} ->
              {:ok, final_acc}

            {:error, reason} ->
              {:error, reason}
          end
      end
    end
  end

  defp filter_rejected_commands(traits, requirements) do
    filtered_traits =
      Enum.reject(traits, fn trait ->
        trait.exec_step.command_name in requirements.graph.rejected_nodes
      end)

    case filtered_traits do
      [] ->
        error_reason = {
          :commands_rejected,
          traits
          |> Enum.map(& &1.exec_step.command_name)
          |> Enum.uniq()
        }

        {:error, error_reason}

      filtered ->
        {:ok, filtered}
    end
  end

  defp check_already_executed(filtered_traits, trail_map, acc) do
    executed_trait =
      Enum.find_value(filtered_traits, fn trait ->
        case trail_map[trait.exec_step.command_name] do
          nil -> nil
          data -> {trait, data}
        end
      end)

    case executed_trait do
      nil ->
        :continue

      {trait, %{added: added}} ->
        if trait.name in added do
          {:already_executed, {:ok, acc}}
        else
          {:trait_mismatch, trait, added}
        end
    end
  end

  defp resolve_trait_dependencies(
         traits,
         acc,
         traits_by_name,
         trail_map,
         required_by
       ) do
    {final_acc, resolved_traits, errors} =
      Enum.reduce(traits, {acc, [], []}, fn trait, {acc, resolved, errors} ->
        case resolve_single_trait_dependencies(trait, acc, traits_by_name, trail_map, required_by) do
          {:ok, new_acc} ->
            {new_acc, [trait | resolved], errors}

          {:error, reason} ->
            {acc, resolved, [reason | errors]}
        end
      end)

    errors = Enum.reverse(errors)
    resolved_traits = Enum.reverse(resolved_traits)

    case {errors, resolved_traits} do
      {[], resolved} when resolved != [] ->
        {:ok, final_acc, resolved_traits}

      {errors, []} ->
        commands_reason = {
          :commands_rejected,
          traits |> Enum.map(& &1.exec_step.command_name) |> Enum.uniq()
        }

        {:error, {:all_traits_failed, [commands_reason | errors]}}

      {errors, _resolved} ->
        {:partial, final_acc, resolved_traits, errors}
    end
  end

  defp resolve_single_trait_dependencies(trait, acc, traits_by_name, trail_map, required_by) do
    case trait.from do
      nil ->
        {:ok, acc}

      from when is_atom(from) ->
        collect_requirements_for_prerequisite_trait(
          trait.name,
          from,
          acc,
          traits_by_name,
          trail_map,
          required_by
        )

      from_any_of when is_list(from_any_of) ->
        if any_prerequisite_trait_satisfied?(from_any_of, traits_by_name, trail_map) do
          {:ok, acc}
        else
          from = hd(from_any_of)

          collect_requirements_for_prerequisite_trait(
            trait.name,
            from,
            acc,
            traits_by_name,
            trail_map,
            required_by
          )
        end
    end
  end

  defp collect_requirements_for_prerequisite_trait(
         trait_name,
         prerequisite,
         acc,
         traits_by_name,
         trail_map,
         required_by
       ) do
    prerequisite_traits = traits_by_name[prerequisite]

    case resolve_traits(acc, prerequisite_traits, traits_by_name, trail_map, required_by) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        {:error, {:prerequisite_unsatisfied, trait_name, prerequisite, reason}}
    end
  end

  defp any_prerequisite_trait_satisfied?(prerequisites, traits_by_name, trail_map) do
    Enum.any?(prerequisites, fn from ->
      traits = traits_by_name[from]

      Enum.any?(traits, fn trait ->
        case trail_map[trait.exec_step.command_name] do
          nil -> false
          %{added: added} -> trait.name in added
        end
      end)
    end)
  end

  def for_command(requirements, command, initial_input, required_by) do
    entities_with_trait_names = extract_parameter_requirements(command, initial_input)
    for_entities_with_trait_names(requirements, entities_with_trait_names, required_by)
  end

  def for_entities_with_trait_names(requirements, entities_with_trait_names, _required_by)
      when map_size(entities_with_trait_names) == 0 do
    requirements
  end

  def for_entities_with_trait_names(
        %{context: context} = initial_requirements,
        entities_with_trait_names,
        required_by
      ) do
    {requirements, command_names} =
      Enum.reduce(
        entities_with_trait_names,
        {initial_requirements, MapSet.new()},
        fn {entity_name, trait_names}, {requirements, command_names} = acc ->
          # duplicated values are produced by extract_parameter_requirements function after recursive calls to
          # `collect_requirements_for_command` function
          trait_names = Enum.uniq(trait_names)

          binding_name = SeedFactory.Context.binding_name(context, entity_name)

          if Map.has_key?(context, binding_name) do
            if trait_names == [] do
              acc
            else
              current_trait_names = SeedFactory.Context.current_trait_names(context, binding_name)

              absent_trait_names = trait_names -- current_trait_names

              if absent_trait_names == [] do
                acc
              else
                %{by_name: traits_by_name} =
                  SeedFactory.Context.fetch_traits!(context, entity_name)

                trail =
                  SeedFactory.Context.fetch_trail(context, binding_name) ||
                    raise """
                    Can't find trail for #{inspect(binding_name)} entity.
                    Please don't put entities that can have traits manually in the context.
                    """

                SeedFactory.Requirements.Restrictions.ensure_not_restricted!(
                  requirements.restrictions,
                  entity_name,
                  binding_name,
                  absent_trait_names,
                  required_by
                )

                collect_requirements_for_traits(
                  acc,
                  absent_trait_names,
                  traits_by_name,
                  entity_name,
                  SeedFactory.Trail.to_map(trail),
                  required_by
                )
              end
            end
          else
            if trait_names == [] do
              command_names_that_can_produce_entity =
                SeedFactory.Context.fetch_command_names_by_entity!(context, entity_name)

              {graph, added_command_names} =
                SeedFactory.Requirements.CommandGraph.register_commands(
                  requirements.graph,
                  command_names_that_can_produce_entity,
                  required_by,
                  []
                )

              requirements = %{requirements | graph: graph}
              {requirements, MapSet.union(command_names, added_command_names)}
            else
              SeedFactory.Requirements.Restrictions.ensure_not_restricted!(
                requirements.restrictions,
                entity_name,
                binding_name,
                trait_names,
                required_by
              )

              %{by_name: traits_by_name} =
                SeedFactory.Context.fetch_traits!(context, entity_name)

              command_names_that_can_produce_entity =
                SeedFactory.Context.fetch_command_names_by_entity!(context, entity_name)

              {graph, added_command_names} =
                SeedFactory.Requirements.CommandGraph.register_commands(
                  requirements.graph,
                  command_names_that_can_produce_entity,
                  required_by,
                  []
                )

              requirements = %{requirements | graph: graph}

              collect_requirements_for_traits(
                {requirements, MapSet.union(command_names, added_command_names)},
                trait_names,
                traits_by_name,
                entity_name,
                %{},
                required_by
              )
            end
          end
        end
      )

    Enum.reduce(command_names, requirements, fn command_name, requirements ->
      command = SeedFactory.Context.fetch_command!(context, command_name)

      added_to_requirements_in_previous_iterations? =
        Map.has_key?(initial_requirements.graph.nodes, command_name)

      removed_from_requirements_in_current_iteration? =
        not Map.has_key?(requirements.graph.nodes, command_name)

      if added_to_requirements_in_previous_iterations? or
           removed_from_requirements_in_current_iteration? or
           anything_was_produced_by_command?(context, command) do
        requirements
      else
        for_command(requirements, command, %{}, command.name)
      end
    end)
  end

  def collect_requirements_for_traits(
        acc,
        trait_names,
        traits_by_name,
        entity_name,
        trail_map,
        required_by
      ) do
    Enum.reduce(trait_names, acc, fn trait_name, acc ->
      case Map.fetch(traits_by_name, trait_name) do
        {:ok, traits} ->
          case resolve_traits(
                 acc,
                 traits,
                 traits_by_name,
                 trail_map,
                 required_by
               ) do
            {:ok, acc} ->
              acc

            {:error, reason} ->
              raise SeedFactory.TraitResolutionError,
                entity: entity_name,
                trait: trait_name,
                required_by: required_by,
                reason: reason
          end

        :error ->
          raise SeedFactory.UnknownTraitError, entity: entity_name, trait: trait_name
      end
    end)
  end

  def extract_parameter_requirements(command, initial_input) do
    extract_parameter_requirements(command.params, %{}, initial_input)
  end

  defp extract_parameter_requirements(params, acc, initial_input) do
    Enum.reduce(params, acc, fn {key, parameter}, acc ->
      case parameter.type do
        :container ->
          extract_parameter_requirements(parameter.params, acc, initial_input)

        :entity ->
          if Map.has_key?(initial_input, key) do
            acc
          else
            trait_names = parameter.with_traits || []
            Map.update(acc, parameter.entity, trait_names, &(trait_names ++ &1))
          end

        _ ->
          acc
      end
    end)
  end

  def anything_was_produced_by_command?(context, command) do
    Enum.any?(command.producing_instructions, fn instruction ->
      binding_name = SeedFactory.Context.binding_name(context, instruction.entity)

      case SeedFactory.Context.fetch_trail(context, binding_name) do
        nil ->
          false

        %{produced_by: {produced_by_command_name, _, _}} ->
          command.name == produced_by_command_name
      end
    end)
  end
end
