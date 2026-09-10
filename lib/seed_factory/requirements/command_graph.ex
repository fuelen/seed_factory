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
end
