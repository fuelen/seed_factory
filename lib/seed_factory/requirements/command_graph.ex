defmodule SeedFactory.Requirements.CommandGraph do
  @moduledoc false

  alias SeedFactory.Requirements.CommandGraph.Node

  defstruct nodes: %{},
            unresolved_conflict_groups: [],
            rejected_nodes: [],
            deferred_resolutions: []

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
    # If a command is already in the graph without conflict groups, it was either never
    # conflicted or was already resolved via a trait. It's safe to link to it directly,
    # even if it has vertical conflicts through other required_by paths.
    case Enum.find(command_names, fn command_name ->
           Map.has_key?(graph.nodes, command_name) and
             graph.nodes[command_name].conflict_groups == []
         end) do
      nil ->
        case analyze_conflict_group(graph, command_names) do
          :new_group ->
            grouped_traits = Enum.group_by(traits, & &1.exec_step.command_name)

            graph =
              command_names
              |> Enum.reduce(graph, fn command_name, graph ->
                add_or_link_node(
                  graph,
                  command_name,
                  required_by,
                  Map.get(grouped_traits, command_name, []),
                  :in_conflict_group
                )
              end)
              |> add_conflict_group(command_names)

            {graph, MapSet.new(command_names)}

          :exists ->
            graph = link_nodes(graph, command_names, required_by, traits)
            {graph, MapSet.new([])}

          {:is_subset, diff} ->
            # Only remove commands from diff if they are NOT in any other conflict groups.
            # This prevents premature removal of commands that are still needed for other conflicts.
            commands_to_remove =
              Enum.filter(diff, fn cmd_name ->
                length(graph.nodes[cmd_name].conflict_groups) == 1
              end)

            graph =
              commands_to_remove
              |> Enum.reduce(graph, &remove_node(&2, &1))
              |> link_nodes(command_names, required_by, traits)

            {graph, MapSet.new([])}

          {:contains_subset, subset} ->
            graph = link_nodes(graph, subset, required_by, traits)
            {graph, MapSet.new([])}
        end

      command_name ->
        traits = Enum.filter(traits, &(&1.exec_step.command_name == command_name))
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
          auto_resolve_conflict_if_possible_in_favour_of(graph, node_name, required_by, traits)
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

  def resolve_conflicts(%__MODULE__{} = graph) do
    case pop_resolvable_deferred_resolution(graph) do
      {node_name, graph} ->
        graph
        |> resolve_conflicts_in_favour_of_the_node(node_name)
        |> resolve_conflicts()

      :none ->
        case graph.unresolved_conflict_groups do
          [] ->
            ensure_deferred_requirements_satisfied!(graph)

          [[primary_node_name | _] | _] ->
            graph
            |> resolve_conflicts_in_favour_of_the_node(primary_node_name)
            |> resolve_conflicts()
        end
    end
  end

  defp pop_resolvable_deferred_resolution(%__MODULE__{} = graph) do
    deferred =
      Enum.find(graph.deferred_resolutions, fn deferred ->
        case graph.nodes[deferred.node_name] do
          nil -> false
          node -> node.conflict_groups != []
        end
      end)

    if deferred do
      {deferred.node_name,
       %{graph | deferred_resolutions: List.delete(graph.deferred_resolutions, deferred)}}
    else
      :none
    end
  end

  defp ensure_deferred_requirements_satisfied!(%__MODULE__{} = graph) do
    Enum.each(graph.deferred_resolutions, fn deferred ->
      if not Map.has_key?(graph.nodes, deferred.node_name) do
        [trait | _] = deferred.traits

        raise SeedFactory.TraitResolutionError,
          entity: trait.entity,
          trait: trait.name,
          required_by: nil,
          reason: {:commands_rejected, [deferred.node_name]}
      end
    end)

    graph
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
         node_name,
         required_by,
         traits
       ) do
    has_conflict? = Map.fetch!(nodes, node_name).conflict_groups != []

    cond do
      not has_conflict? ->
        graph

      not anything_in_vertical_conflicts?(nodes, node_name) ->
        resolve_conflicts_in_favour_of_the_node(graph, node_name)

      required_by == nil ->
        # A top-level request leaves the command no alternative, but resolving now
        # could wrongly remove nodes whose own conflicts are not settled yet.
        # Remember the demand and let resolve_conflicts apply it.
        deferred = %{node_name: node_name, traits: traits}
        %{graph | deferred_resolutions: [deferred | graph.deferred_resolutions]}

      true ->
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
    nodes = graph.nodes

    in_counts =
      Map.new(nodes, fn {name, node} ->
        count = Enum.count(node.requires, &Map.has_key?(nodes, &1))
        {name, count}
      end)

    queue = for {name, 0} <- in_counts, do: name

    sorted_nodes = do_topsort(queue, [], nodes, in_counts)

    if length(sorted_nodes) != map_size(nodes) do
      commands_in_cycles =
        Enum.sort(Map.keys(nodes) -- Enum.map(sorted_nodes, & &1.name))

      raise SeedFactory.CircularDependencyError, commands: commands_in_cycles
    end

    sorted_nodes
  end

  defp do_topsort([], acc, _nodes, _in_counts), do: Enum.reverse(acc)

  defp do_topsort([name | rest], acc, nodes, in_counts) do
    node = Map.fetch!(nodes, name)

    {new_ready, in_counts} =
      Enum.flat_map_reduce(node.required_by, in_counts, fn
        {nil, _}, counts ->
          {[], counts}

        {dep, _}, counts ->
          if Map.has_key?(nodes, dep) do
            new_count = counts[dep] - 1
            counts = Map.put(counts, dep, new_count)
            if new_count == 0, do: {[dep], counts}, else: {[], counts}
          else
            {[], counts}
          end
      end)

    do_topsort(rest ++ new_ready, [node | acc], nodes, in_counts)
  end

  # Conflict resolution can remove the producer a node was linked to while another
  # producer of the same entity survives in the plan. Without a fresh edge the
  # execution order between them is left to the topological sort tie-break.
  def link_producers_of_required_entities(%__MODULE__{} = graph, context) do
    Enum.reduce(graph.nodes, graph, fn {node_name, node}, graph ->
      command = SeedFactory.Context.fetch_command!(context, node_name)

      command.required_entities
      |> Map.keys()
      |> Enum.reduce(graph, fn entity_name, graph ->
        binding_name = SeedFactory.Context.binding_name(context, entity_name)

        live_producers =
          if Map.has_key?(context, binding_name) do
            []
          else
            context
            |> SeedFactory.Context.fetch_command_names_by_entity!(entity_name)
            |> Enum.filter(&(&1 != node_name and Map.has_key?(graph.nodes, &1)))
          end

        if live_producers == [] or Enum.any?(live_producers, &(&1 in node.requires)) do
          graph
        else
          link_nodes(graph, live_producers, node_name, [])
        end
      end)
    end)
  end

  def deprioritize_nodes_that_delete_entities_or_remove_traits(graph, context) do
    nodes = graph.nodes

    Enum.reduce(nodes, graph, fn {node_name, graph_node}, graph ->
      command = SeedFactory.Context.fetch_command!(context, node_name)

      sibling_node_names =
        graph_node.requires
        |> Enum.flat_map(fn requires_node_name ->
          Map.keys(Map.fetch!(nodes, requires_node_name).required_by)
        end)
        |> Enum.uniq()
        |> Enum.reject(&(&1 in [nil, node_name]))

      node_names_that_delete_entities =
        Enum.flat_map(command.deleting_instructions, fn %{entity: entity} ->
          Enum.filter(sibling_node_names, fn sibling ->
            Map.has_key?(
              SeedFactory.Context.fetch_command!(context, sibling).required_entities,
              entity
            )
          end)
        end)

      node_names_that_remove_traits =
        Enum.flat_map(command.updating_instructions, fn %{entity: entity} ->
          potentially_removes_traits =
            (SeedFactory.Context.get_traits(context, entity)[:by_command_name][command.name] ||
               [])
            |> Enum.flat_map(&List.wrap(&1.from))
            |> MapSet.new()

          Enum.filter(sibling_node_names, fn sibling ->
            case Map.fetch(
                   SeedFactory.Context.fetch_command!(context, sibling).required_entities,
                   entity
                 ) do
              {:ok, required_entities} ->
                required_entities
                |> MapSet.intersection(potentially_removes_traits)
                |> Enum.any?()

              :error ->
                false
            end
          end)
        end)

      node_names_to_link =
        node_names_that_delete_entities ++ node_names_that_remove_traits

      link_nodes(graph, node_names_to_link, node_name, [])
    end)
  end
end
