defmodule SeedFactory.Requirements.CommandGraph do
  @moduledoc false

  alias SeedFactory.Requirements.CommandGraph.Node

  defstruct nodes: %{}, unresolved_conflict_groups: [], rejected_nodes: []

  def new do
    %__MODULE__{}
  end

  def register_commands(graph, command_names, required_by, traits)

  def register_commands(graph, [command_name], required_by, traits) do
    graph =
      add_or_link_node(
        graph,
        command_name,
        required_by,
        traits,
        :no_conflict
      )

    {graph, MapSet.new([command_name])}
  end

  def register_commands(graph, command_names, required_by, traits)
      when command_names != [] do
    # if the command can be found in graph, and it doesn't have any conflict, it means, that it was requested
    # without ambiguity, so we can skip conflict resolution for the command
    case Enum.find(
           command_names,
           fn command_name ->
             Map.has_key?(graph.nodes, command_name) and
               not node_or_anything_in_vertical_conflicts?(graph, command_name)
           end
         ) do
      nil ->
        case analyze_conflict_group(graph, command_names) do
          :new_group ->
            graph =
              command_names
              |> Enum.reduce(graph, fn command_name, graph ->
                add_or_link_node(
                  graph,
                  command_name,
                  required_by,
                  traits,
                  :in_conflict_group
                )
              end)
              |> add_conflict_group(command_names)

            {graph, MapSet.new(command_names)}

          :exists ->
            graph = link_nodes(graph, command_names, required_by, traits)
            {graph, MapSet.new([])}

          {:is_subset, diff} ->
            graph =
              diff
              |> Enum.reduce(graph, &remove_node(&2, &1))
              |> link_nodes(command_names, required_by, traits)

            {graph, MapSet.new([])}

          {:contains_subset, subset} ->
            graph = link_nodes(graph, subset, required_by, traits)
            {graph, MapSet.new([])}
        end

      command_name ->
        graph = link_nodes(graph, command_name, required_by, traits)
        {graph, MapSet.new()}
    end
  end

  defp add_node(%__MODULE__{} = graph, %Node{} = node) do
    nodes = Map.put(graph.nodes, node.name, node)

    node.required_by
    |> Map.keys()
    |> Enum.reduce(%{graph | nodes: nodes}, &require_node(&2, &1, node.name))
  end

  def remove_node(%__MODULE__{} = graph, node_name) do
    node = Map.fetch!(graph.nodes, node_name)

    nodes =
      graph.nodes
      |> Map.delete(node_name)
      |> unrequire_node_names(node_name, Map.keys(node.required_by))

    graph = %{graph | nodes: nodes, rejected_nodes: [node_name | graph.rejected_nodes]}

    graph =
      remove_node_name_from_conflict_groups_if_present(graph, node)

    Enum.reduce(
      node.requires,
      graph,
      &remove_node_while_required_by_is_empty(&2, &1, node_name)
    )
  end

  defp remove_node_while_required_by_is_empty(graph, node_name, deleted_required_by) do
    node = Map.fetch!(graph.nodes, node_name)
    new_required_by = Map.delete(node.required_by, deleted_required_by)

    if Enum.empty?(new_required_by) do
      remove_node(graph, node_name)
    else
      nodes = Map.update!(graph.nodes, node_name, &Node.set_required_by(&1, new_required_by))

      %{graph | nodes: nodes}
    end
  end

  defp remove_node_name_from_conflict_groups_if_present(graph, %Node{conflict_groups: []}) do
    graph
  end

  defp remove_node_name_from_conflict_groups_if_present(
         graph,
         %Node{name: node_name_to_remove, conflict_groups: conflict_groups}
       ) do
    conflict_groups
    |> Enum.reduce(graph, fn conflict_group, graph ->
      node_names_to_update = List.delete(conflict_group, node_name_to_remove)

      new_conflict_group =
        case node_names_to_update do
          [_] -> []
          group -> group
        end

      unresolved_conflict_groups =
        List.delete(graph.unresolved_conflict_groups, conflict_group)

      unresolved_conflict_groups =
        if new_conflict_group == [] do
          unresolved_conflict_groups
        else
          [new_conflict_group | unresolved_conflict_groups]
        end

      update_node =
        if new_conflict_group == [] do
          &Node.remove_conflict_group(&1, conflict_group)
        else
          &Node.replace_conflict_group(&1, conflict_group, new_conflict_group)
        end

      nodes =
        Enum.reduce(node_names_to_update, graph.nodes, fn node_name, nodes ->
          Map.update!(nodes, node_name, update_node)
        end)

      %{graph | nodes: nodes, unresolved_conflict_groups: unresolved_conflict_groups}
    end)
  end

  defp unrequire_node_names(nodes, node_name_to_remove, target_node_names) do
    Enum.reduce(target_node_names, nodes, fn
      nil, nodes ->
        nodes

      required_by_node_name, nodes ->
        if Map.has_key?(nodes, required_by_node_name) do
          Map.update!(nodes, required_by_node_name, &Node.unrequire_node(&1, node_name_to_remove))
        else
          nodes
        end
    end)
  end

  def analyze_conflict_group(%__MODULE__{} = graph, conflict_group_to_analyze) do
    unresolved_conflict_groups = graph.unresolved_conflict_groups
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

  defp require_node(%__MODULE__{} = graph, node_name, node_name_to_add) do
    case node_name do
      nil ->
        graph

      node_name ->
        nodes = Map.update!(graph.nodes, node_name, &Node.require_node(&1, node_name_to_add))
        %{graph | nodes: nodes}
    end
  end

  defp merge_required_by(%__MODULE__{} = graph, node_name, required_by) do
    nodes = Map.update!(graph.nodes, node_name, &Node.merge_required_by(&1, required_by))
    %{graph | nodes: nodes}
  end

  def add_or_link_node(graph, node_name, required_by, traits, type) when is_atom(required_by) do
    if Map.has_key?(graph.nodes, node_name) do
      graph =
        link_nodes(graph, node_name, required_by, traits)

      case type do
        :in_conflict_group ->
          graph

        :no_conflict ->
          auto_resolve_conflict_if_possible_in_favour_of(graph, node_name)
      end
    else
      node = Node.new(%{name: node_name, required_by: %{required_by => traits}})

      add_node(graph, node)
    end
  end

  def add_conflict_group(%__MODULE__{} = graph, conflict_group) do
    nodes =
      Enum.reduce(conflict_group, graph.nodes, fn node_name, nodes ->
        Map.update!(nodes, node_name, fn node ->
          Node.add_conflict_group(node, conflict_group)
        end)
      end)

    %{
      graph
      | unresolved_conflict_groups: [conflict_group | graph.unresolved_conflict_groups],
        nodes: nodes
    }
  end

  def link_nodes(graph, node_names, required_by, traits)
      when is_list(node_names) and is_list(traits) do
    grouped_traits =
      traits
      |> Enum.group_by(& &1.exec_step.command_name)

    Enum.reduce(
      node_names,
      graph,
      &link_nodes(&2, &1, required_by, Map.get(grouped_traits, &1, []))
    )
  end

  def link_nodes(graph, node_name, required_by, traits)
      when is_atom(node_name) and is_list(traits) do
    graph
    |> merge_required_by(node_name, %{required_by => traits})
    |> require_node(required_by, node_name)
  end

  def resolve_conflicts(%{unresolved_conflict_groups: []} = graph) do
    graph
  end

  def resolve_conflicts(%{unresolved_conflict_groups: [[primary_node_name | _] | _]} = graph) do
    graph
    |> resolve_conflicts_in_favour_of_the_node(primary_node_name)
    |> resolve_conflicts()
  end

  defp resolve_conflicts_in_favour_of_the_node(graph, node_name_to_keep) do
    node = Map.fetch!(graph.nodes, node_name_to_keep)

    all_node_names_in_conflict_groups =
      node.conflict_groups
      |> List.flatten()
      |> Enum.uniq()

    Enum.reduce(
      all_node_names_in_conflict_groups,
      graph,
      fn node_name, graph ->
        if node_name == node_name_to_keep do
          graph
        else
          remove_node(graph, node_name)
        end
      end
    )
  end

  def node_or_anything_in_vertical_conflicts?(%__MODULE__{nodes: nodes}, node_name) do
    Map.fetch!(nodes, node_name).conflict_groups != [] or
      anything_in_vertical_conflicts?(nodes, node_name)
  end

  defp anything_in_vertical_conflicts?(nodes, node_name) do
    Enum.any?(Map.fetch!(nodes, node_name).required_by, fn
      {nil, _traits} ->
        false

      {node_name, _traits} ->
        Map.fetch!(nodes, node_name).conflict_groups != [] or
          anything_in_vertical_conflicts?(nodes, node_name)
    end)
  end

  defp auto_resolve_conflict_if_possible_in_favour_of(
         %__MODULE__{nodes: nodes} = graph,
         node_name
       ) do
    has_conflict? = Map.fetch!(nodes, node_name).conflict_groups != []

    if has_conflict? and
         not anything_in_vertical_conflicts?(nodes, node_name) do
      resolve_conflicts_in_favour_of_the_node(graph, node_name)
    else
      graph
    end
  end

  def delete_explicitly_requested_nodes(graph) do
    Enum.reduce(graph.nodes, graph, fn {node_name, node}, acc ->
      if Node.requested_explicitly?(node) do
        remove_node_unsafe(acc, node_name)
      else
        acc
      end
    end)
  end

  defp remove_node_unsafe(graph, node_name_to_delete)
       when is_atom(node_name_to_delete) do
    case graph.nodes[node_name_to_delete] do
      nil ->
        graph

      node ->
        Enum.reduce(
          Map.keys(node.required_by),
          %{graph | nodes: Map.delete(graph.nodes, node_name_to_delete)},
          &remove_node_unsafe(&2, &1)
        )
    end
  end

  def topologically_sorted_nodes(graph) do
    graph.nodes
    |> Enum.reduce(Graph.new(), fn {node_name, %{required_by: required_by}}, g ->
      Enum.reduce(required_by, g, fn {dependent_node, _traits}, g ->
        Graph.add_edge(g, node_name, dependent_node)
      end)
    end)
    |> Graph.topsort()
    |> Enum.flat_map(fn node_name ->
      # node should not be executed if it can be found in `required_by` field but not in `graph.nodes` by key.
      # it can't be found if it is nil (top level required_by value - represents root of the graph)
      # or if it was removed in `pre_exec` by `delete_explicitly_requested_nodes`
      case graph.nodes[node_name] do
        nil -> []
        node -> [node]
      end
    end)
  end

  def deprioritize_nodes_that_delete_entities_or_remove_traits(graph, context) do
    nodes = graph.nodes

    Enum.reduce(nodes, graph, fn {node_name, graph_node}, graph ->
      command = SeedFactory.Context.fetch_command!(context, node_name)

      node_names_that_delete_entities =
        Enum.flat_map(command.deleting_instructions, fn %{entity: entity} ->
          graph_node.requires
          |> Enum.flat_map(fn requires_node_name ->
            Map.keys(Map.fetch!(nodes, requires_node_name).required_by)
          end)
          |> Enum.filter(fn required_by_node_name ->
            required_by_node_name not in [nil, node_name] and
              Map.has_key?(
                SeedFactory.Context.fetch_command!(context, required_by_node_name).required_entities,
                entity
              )
          end)
        end)

      node_names_that_remove_traits =
        Enum.flat_map(command.updating_instructions, fn %{entity: entity} ->
          potentially_removes_traits =
            Enum.flat_map(
              SeedFactory.Context.get_traits(context, entity)[:by_command_name][command.name] ||
                [],
              fn trait ->
                if is_nil(trait.from) do
                  []
                else
                  [trait.from]
                end
              end
            )
            |> MapSet.new()

          graph_node.requires
          |> Enum.flat_map(fn requires_node_name ->
            Map.keys(Map.fetch!(nodes, requires_node_name).required_by)
          end)
          |> Enum.uniq()
          |> Enum.filter(fn
            required_by_node_name ->
              if required_by_node_name in [nil, node_name] do
                false
              else
                case Map.fetch(
                       SeedFactory.Context.fetch_command!(context, required_by_node_name).required_entities,
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

      node_names_to_link =
        node_names_that_delete_entities ++ node_names_that_remove_traits

      link_nodes(graph, node_names_to_link, node_name, [])
    end)
  end
end
