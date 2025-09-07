defmodule SeedFactory.Requirements do
  @moduledoc false

  defmodule Command do
    @moduledoc false
    @enforce_keys [:name, :required_by]

    @derive {Inspect, optional: [:conflict_groups, :requires]}
    defstruct [:name, :required_by, conflict_groups: [], requires: MapSet.new()]

    def new(params) do
      struct!(__MODULE__, params)
    end

    def add_conflict_group(%Command{} = command, conflict_group) do
      conflict_groups = [conflict_group | command.conflict_groups]
      %{command | conflict_groups: conflict_groups}
    end

    def replace_conflict_group(%Command{} = command, old, new) do
      conflict_groups = [new | List.delete(command.conflict_groups, old)]
      %{command | conflict_groups: conflict_groups}
    end

    def remove_conflict_group(%Command{} = command, conflict_group) do
      conflict_groups = List.delete(command.conflict_groups, conflict_group)
      %{command | conflict_groups: conflict_groups}
    end

    def require_command(%Command{} = command, command_name_to_add) do
      %{command | requires: MapSet.put(command.requires, command_name_to_add)}
    end

    def unrequire_command(%Command{} = command, command_name_to_remove) do
      %{command | requires: MapSet.delete(command.requires, command_name_to_remove)}
    end

    def set_required_by(%Command{} = command, required_by) do
      %{command | required_by: required_by}
    end

    def merge_required_by(%Command{} = command, required_by) do
      %{
        command
        | required_by: Map.merge(command.required_by, required_by, fn _, v1, v2 -> v1 ++ v2 end)
      }
    end

    def requested_explicitly?(%Command{} = command) do
      Map.has_key?(command.required_by, nil)
    end
  end

  defstruct commands: %{}, unresolved_conflict_groups: [], rejected_commands: []

  def init do
    %__MODULE__{}
  end

  defp add_command(%__MODULE__{} = requirements, %__MODULE__.Command{} = command) do
    commands = Map.put(requirements.commands, command.name, command)

    command.required_by
    |> Map.keys()
    |> Enum.reduce(
      %{requirements | commands: commands},
      &require_command(&2, &1, command.name)
    )
  end

  def remove_command(%__MODULE__{} = requirements, command_name) do
    command = Map.fetch!(requirements.commands, command_name)

    commands =
      requirements.commands
      |> Map.delete(command_name)
      |> unrequire_command_names(command_name, Map.keys(command.required_by))

    requirements = %{
      requirements
      | commands: commands,
        rejected_commands: [command_name | requirements.rejected_commands]
    }

    requirements =
      remove_command_name_from_conflict_groups_if_present(
        requirements,
        command.conflict_groups,
        command_name
      )

    Enum.reduce(
      command.requires,
      requirements,
      &remove_command_while_required_by_is_empty(&2, &1, command_name)
    )
  end

  defp remove_command_while_required_by_is_empty(
         requirements,
         command_name,
         deleted_required_by
       ) do
    command = Map.fetch!(requirements.commands, command_name)
    new_required_by = Map.delete(command.required_by, deleted_required_by)

    if Enum.empty?(new_required_by) do
      remove_command(requirements, command_name)
    else
      commands =
        Map.update!(
          requirements.commands,
          command_name,
          &__MODULE__.Command.set_required_by(&1, new_required_by)
        )

      %{requirements | commands: commands}
    end
  end

  defp remove_command_name_from_conflict_groups_if_present(
         requirements,
         [],
         _command_name_to_remove
       ) do
    requirements
  end

  defp remove_command_name_from_conflict_groups_if_present(
         requirements,
         conflict_groups,
         command_name_to_remove
       ) do
    conflict_groups
    |> Enum.reduce(requirements, fn conflict_group, requirements ->
      command_names_to_update = List.delete(conflict_group, command_name_to_remove)

      new_conflict_group =
        case command_names_to_update do
          [_] -> []
          group -> group
        end

      if new_conflict_group == conflict_group do
        requirements
      else
        unresolved_conflict_groups =
          List.delete(requirements.unresolved_conflict_groups, conflict_group)

        unresolved_conflict_groups =
          if new_conflict_group == [] do
            unresolved_conflict_groups
          else
            [new_conflict_group | unresolved_conflict_groups]
          end

        update_command =
          if new_conflict_group == [] do
            &__MODULE__.Command.remove_conflict_group(&1, conflict_group)
          else
            &__MODULE__.Command.replace_conflict_group(&1, conflict_group, new_conflict_group)
          end

        commands =
          Enum.reduce(command_names_to_update, requirements.commands, fn command_name, commands ->
            Map.update!(commands, command_name, update_command)
          end)

        %{
          requirements
          | commands: commands,
            unresolved_conflict_groups: unresolved_conflict_groups
        }
      end
    end)
  end

  defp unrequire_command_names(
         commands,
         command_name_to_remove,
         target_command_names
       ) do
    Enum.reduce(target_command_names, commands, fn
      nil, commands ->
        commands

      required_by_command_name, commands ->
        if Map.has_key?(commands, required_by_command_name) do
          Map.update!(
            commands,
            required_by_command_name,
            &__MODULE__.Command.unrequire_command(&1, command_name_to_remove)
          )
        else
          commands
        end
    end)
  end

  def analyze_conflict_group(%__MODULE__{} = requirements, conflict_group_to_analyze) do
    unresolved_conflict_groups = requirements.unresolved_conflict_groups
    conflict_group_to_analyze_mapset = MapSet.new(conflict_group_to_analyze)

    Enum.find_value(unresolved_conflict_groups, :new_group, fn unresolved_conflict_group ->
      unresolved_conflict_group_mapset = MapSet.new(unresolved_conflict_group)

      cond do
        conflict_group_to_analyze == unresolved_conflict_group ->
          :exists

        MapSet.subset?(conflict_group_to_analyze_mapset, unresolved_conflict_group_mapset) ->
          {:is_subset,
           MapSet.difference(unresolved_conflict_group_mapset, conflict_group_to_analyze_mapset)}

        MapSet.subset?(unresolved_conflict_group_mapset, conflict_group_to_analyze_mapset) ->
          {:contains_subset, unresolved_conflict_group}

        true ->
          false
      end
    end)
  end

  def require_command(
        %__MODULE__{} = requirements,
        command_name,
        command_name_to_add
      ) do
    case command_name do
      nil ->
        requirements

      command_name ->
        commands =
          Map.update!(
            requirements.commands,
            command_name,
            &__MODULE__.Command.require_command(&1, command_name_to_add)
          )

        %{requirements | commands: commands}
    end
  end

  def merge_required_by(%__MODULE__{} = requirements, command_name, required_by) do
    commands =
      Map.update!(
        requirements.commands,
        command_name,
        &__MODULE__.Command.merge_required_by(&1, required_by)
      )

    %{requirements | commands: commands}
  end

  def add_or_link_command(
        requirements,
        command_name,
        required_by,
        traits,
        type
      )
      when is_atom(required_by) do
    if Map.has_key?(requirements.commands, command_name) do
      requirements =
        link_commands(requirements, command_name, required_by, traits)

      case type do
        :in_conflict_group ->
          requirements

        :no_conflict ->
          auto_resolve_conflict_if_possible_in_favour_of(
            requirements,
            command_name
          )
      end
    else
      command =
        SeedFactory.Requirements.Command.new(%{
          name: command_name,
          required_by: %{required_by => traits}
        })

      add_command(requirements, command)
    end
  end

  def add_conflict_group(%__MODULE__{} = requirements, conflict_group) do
    commands =
      Enum.reduce(conflict_group, requirements.commands, fn command_name, commands ->
        Map.update!(commands, command_name, fn command ->
          __MODULE__.Command.add_conflict_group(command, conflict_group)
        end)
      end)

    %{
      requirements
      | unresolved_conflict_groups: [conflict_group | requirements.unresolved_conflict_groups],
        commands: commands
    }
  end

  def link_commands(requirements, command_names, required_by, traits)
      when is_list(command_names) and is_list(traits) do
    grouped_traits =
      traits
      |> Enum.group_by(& &1.exec_step.command_name)

    Enum.reduce(
      command_names,
      requirements,
      &link_commands(&2, &1, required_by, Map.get(grouped_traits, &1, []))
    )
  end

  def link_commands(requirements, command_name, required_by, traits)
      when is_atom(command_name) and is_list(traits) do
    requirements
    |> merge_required_by(command_name, %{required_by => traits})
    |> require_command(required_by, command_name)
  end

  def resolve_conflicts(%{unresolved_conflict_groups: []} = requirements) do
    requirements
  end

  def resolve_conflicts(
        %{unresolved_conflict_groups: [[primary_command_name | _] | _]} = requirements
      ) do
    requirements
    |> resolve_conflicts_in_favour_of_the_command(primary_command_name)
    |> resolve_conflicts()
  end

  defp resolve_conflicts_in_favour_of_the_command(requirements, command_name_to_keep) do
    command = Map.fetch!(requirements.commands, command_name_to_keep)

    all_command_names_in_conflict_groups =
      command.conflict_groups
      |> List.flatten()
      |> Enum.uniq()

    Enum.reduce(
      all_command_names_in_conflict_groups,
      requirements,
      fn command_name, requirements ->
        if command_name == command_name_to_keep do
          requirements
        else
          remove_command(requirements, command_name)
        end
      end
    )
  end

  def command_or_anything_in_vertical_conflicts?(commands, command_name) do
    Map.fetch!(commands, command_name).conflict_groups != [] or
      anything_in_vertical_conflicts?(commands, command_name)
  end

  defp anything_in_vertical_conflicts?(commands, command_name) do
    Enum.any?(Map.fetch!(commands, command_name).required_by, fn
      {nil, _traits} ->
        false

      {command_name, _traits} ->
        command_or_anything_in_vertical_conflicts?(commands, command_name)
    end)
  end

  def auto_resolve_conflict_if_possible_in_favour_of(requirements, command_name) do
    has_conflict? = Map.fetch!(requirements.commands, command_name).conflict_groups != []

    if has_conflict? and
         not anything_in_vertical_conflicts?(requirements.commands, command_name) do
      resolve_conflicts_in_favour_of_the_command(requirements, command_name)
    else
      requirements
    end
  end

  def delete_explicitly_requested_commands(requirements) do
    Enum.reduce(requirements.commands, requirements, fn {command_name, command}, acc ->
      if __MODULE__.Command.requested_explicitly?(command) do
        remove_command_unsafe(acc, command_name)
      else
        acc
      end
    end)
  end

  defp remove_command_unsafe(requirements, command_name_to_delete)
       when is_atom(command_name_to_delete) do
    case requirements.commands[command_name_to_delete] do
      nil ->
        requirements

      command ->
        Enum.reduce(
          Map.keys(command.required_by),
          %{requirements | commands: Map.delete(requirements.commands, command_name_to_delete)},
          &remove_command_unsafe(&2, &1)
        )
    end
  end

  def topologically_sorted_commands(requirements) do
    requirements.commands
    |> Enum.reduce(Graph.new(), fn {command_name, %{required_by: required_by}}, graph ->
      Enum.reduce(required_by, graph, fn {dependent_command, _traits}, graph ->
        Graph.add_edge(graph, command_name, dependent_command)
      end)
    end)
    |> Graph.topsort()
    |> Enum.flat_map(fn command_name ->
      # command should not be executed if it can be found in `required_by` field but not in `requirements.commands` by key.
      # it can't be found if it is nil (top level required_by value - represents root of the graph)
      # or if it was removed in `pre_exec` by `delete_explicitly_requested_commands`
      case requirements.commands[command_name] do
        nil -> []
        command -> [command]
      end
    end)
  end

  def deprioritize_commands_that_delete_entities_or_remove_traits(
        requirements,
        fetch_command_definition_by_name!,
        get_traits
      ) do
    commands = requirements.commands

    Enum.reduce(commands, requirements, fn {command_name, requirements_command}, requirements ->
      command = fetch_command_definition_by_name!.(command_name)

      command_names_that_delete_entities =
        Enum.flat_map(command.deleting_instructions, fn %{entity: entity} ->
          requirements_command.requires
          |> Enum.flat_map(fn requires_command_name ->
            Map.keys(Map.fetch!(commands, requires_command_name).required_by)
          end)
          |> Enum.filter(fn required_by_command_name ->
            required_by_command_name not in [nil, command_name] and
              Map.has_key?(
                fetch_command_definition_by_name!.(required_by_command_name).required_entities,
                entity
              )
          end)
        end)

      command_names_that_remove_traits =
        Enum.flat_map(command.updating_instructions, fn %{entity: entity} ->
          potentially_removes_traits =
            Enum.flat_map(get_traits.(entity)[:by_command_name][command.name] || [], fn trait ->
              if is_nil(trait.from) do
                []
              else
                [trait.from]
              end
            end)
            |> MapSet.new()

          requirements_command.requires
          |> Enum.flat_map(fn requires_command_name ->
            Map.keys(Map.fetch!(commands, requires_command_name).required_by)
          end)
          |> Enum.uniq()
          |> Enum.filter(fn
            required_by_command_name ->
              if required_by_command_name in [nil, command_name] do
                false
              else
                case Map.fetch(
                       fetch_command_definition_by_name!.(required_by_command_name).required_entities,
                       entity
                     ) do
                  {:ok, required_entities} ->
                    required_entities
                    |> MapSet.intersection(potentially_removes_traits)
                    |> Enum.any?()

                  :error ->
                    false
                end
              end
          end)
        end)

      command_names_to_link =
        command_names_that_delete_entities ++ command_names_that_remove_traits

      link_commands(requirements, command_names_to_link, command_name, [])
    end)
  end
end
