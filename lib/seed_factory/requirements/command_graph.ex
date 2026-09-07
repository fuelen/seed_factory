defmodule SeedFactory.Requirements.CommandGraph do
  @moduledoc false

  alias SeedFactory.Requirements.CommandGraph.Node

  # The final execution graph the solver materializes its plan into: `nodes`
  # maps command names to nodes whose `required_by`/`requires` edges drive the
  # topological sort.
  defstruct nodes: %{}

  def link_nodes(graph, node_name, required_by, traits)
      when is_atom(node_name) and is_list(traits) do
    graph
    |> merge_required_by(node_name, %{required_by => traits})
    |> require_node(required_by, node_name)
  end

  defp merge_required_by(%__MODULE__{} = graph, node_name, required_by) do
    nodes = Map.update!(graph.nodes, node_name, &Node.merge_required_by(&1, required_by))
    %{graph | nodes: nodes}
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

  def delete_explicitly_requested_nodes(graph) do
    Enum.reduce(graph.nodes, graph, fn {node_name, node}, acc ->
      if Node.requested_explicitly?(node) do
        remove_node_unsafe(acc, node_name)
      else
        acc
      end
    end)
  end

  # Deliberately leaves required_by entries pointing at the deleted nodes:
  # resolved_args reads the trait args they carry when the kept dependencies
  # are executed. Consumers of the graph must skip dead references instead.
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

    queue =
      Enum.reduce(in_counts, :queue.new(), fn
        {name, 0}, queue -> :queue.in(name, queue)
        _, queue -> queue
      end)

    sorted_nodes = do_topsort(queue, [], nodes, in_counts)

    if length(sorted_nodes) != map_size(nodes) do
      commands_in_cycles = Map.keys(nodes) -- Enum.map(sorted_nodes, & &1.name)

      raise SeedFactory.CircularDependencyError, commands: commands_in_cycles
    end

    sorted_nodes
  end

  defp do_topsort(queue, acc, nodes, in_counts) do
    case :queue.out(queue) do
      {:empty, _} ->
        Enum.reverse(acc)

      {{:value, name}, queue} ->
        node = Map.fetch!(nodes, name)

        {queue, in_counts} =
          Enum.reduce(node.required_by, {queue, in_counts}, fn
            {nil, _}, acc ->
              acc

            {dep, _}, {queue, counts} ->
              if Map.has_key?(nodes, dep) do
                new_count = counts[dep] - 1
                counts = Map.put(counts, dep, new_count)
                if new_count == 0, do: {:queue.in(dep, queue), counts}, else: {queue, counts}
              else
                {queue, counts}
              end
          end)

        do_topsort(queue, [node | acc], nodes, in_counts)
    end
  end

  # The solver links every demand to a producer, so this pass matters only for
  # graphs it could not fully link (a command supplying its own parameter in
  # the relaxed diagnosis pass): the safety net below turns such plans into a
  # loud error instead of an execution crash.
  def link_producers_of_required_entities(%__MODULE__{} = graph, context) do
    Enum.reduce(graph.nodes, graph, fn {node_name, node}, graph ->
      command = SeedFactory.Context.fetch_command!(context, node_name)

      command.required_entities
      |> Map.keys()
      |> Enum.reduce(graph, fn entity_name, graph ->
        binding_name = SeedFactory.Context.binding_name(context, entity_name)

        if Map.has_key?(context, binding_name) do
          graph
        else
          live_producers =
            context
            |> SeedFactory.Context.fetch_command_names_by_entity!(entity_name)
            |> Enum.filter(&(&1 != node_name and Map.has_key?(graph.nodes, &1)))

          cond do
            live_producers == [] ->
              # Guaranteed crash at execution. The solver raises during
              # planning already, so this is a safety net for paths it does
              # not track.
              raise SeedFactory.UnproducibleEntityError,
                entity: entity_name,
                required_by: node_name,
                commands:
                  SeedFactory.Context.fetch_command_names_by_entity!(context, entity_name),
                cause: :not_planned

            Enum.any?(live_producers, &(&1 in node.requires)) ->
              graph

            true ->
              Enum.reduce(live_producers, graph, &link_nodes(&2, &1, node_name, []))
          end
        end
      end)
    end)
  end

  def deprioritize_nodes_that_delete_entities_or_remove_traits(graph, context) do
    Enum.reduce(Map.keys(graph.nodes), graph, fn node_name, graph ->
      command = SeedFactory.Context.fetch_command!(context, node_name)

      consumers_of_deleted_entities =
        Enum.flat_map(command.deleting_instructions, fn %{entity: entity} ->
          consumer_node_names(graph, context, node_name, entity, nil)
        end)

      consumers_of_removed_traits =
        Enum.flat_map(command.updating_instructions, fn %{entity: entity} ->
          potentially_removes_traits =
            (SeedFactory.Context.get_traits(context, entity)[:by_command_name][command.name] ||
               [])
            |> Enum.flat_map(&List.wrap(&1.from))
            |> MapSet.new()

          consumer_node_names(graph, context, node_name, entity, potentially_removes_traits)
        end)

      Enum.reduce(
        consumers_of_deleted_entities ++ consumers_of_removed_traits,
        graph,
        fn consumer, graph -> link_unless_ordered(graph, consumer, node_name) end
      )
    end)
  end

  # Nodes whose command requires the entity, regardless of shared plan nodes:
  # a consumer of an entity that already sits in the context has no plan edge
  # for it, yet still has to run before the entity's deleter. With a trait
  # set given, only consumers requiring one of those traits count.
  defp consumer_node_names(graph, context, node_name, entity, trait_names) do
    for name <- Map.keys(graph.nodes),
        name != node_name,
        required_traits =
          Map.get(SeedFactory.Context.fetch_command!(context, name).required_entities, entity),
        required_traits != nil,
        trait_names == nil or Enum.any?(MapSet.intersection(required_traits, trait_names)),
        do: name
  end

  # Orders `then_name` after `first_name` unless the graph already orders them
  # the other way, as a legitimate interleave chain does with the consumer of
  # a re-produced instance.
  defp link_unless_ordered(graph, first_name, then_name) do
    if requires_transitively?(graph.nodes, first_name, then_name) do
      graph
    else
      link_nodes(graph, first_name, then_name, [])
    end
  end

  defp requires_transitively?(nodes, from, target) do
    walk_requires([from], nodes, target, MapSet.new())
  end

  defp walk_requires([], _nodes, _target, _seen), do: false

  defp walk_requires([name | rest], nodes, target, seen) do
    deps = Map.fetch!(nodes, name).requires

    if MapSet.member?(deps, target) do
      true
    else
      new = MapSet.difference(deps, seen)
      walk_requires(MapSet.to_list(new) ++ rest, nodes, target, MapSet.union(seen, new))
    end
  end
end
