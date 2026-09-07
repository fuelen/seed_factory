defmodule SeedFactory.Requirements do
  @moduledoc false

  alias SeedFactory.Requirements.CommandGraph
  alias SeedFactory.Requirements.Solver

  @enforce_keys [:context, :graph]
  defstruct [:context, :graph]

  def build(context, entities_with_trait_names) do
    %__MODULE__{context: context, graph: Solver.build_graph(context, entities_with_trait_names)}
  end

  def build_for_pre_produce(context, entities_with_trait_names) do
    %__MODULE__{
      context: context,
      graph: Solver.build_graph_for_pre_produce(context, entities_with_trait_names)
    }
  end

  def build_for_command(context, command, initial_input) do
    %__MODULE__{
      context: context,
      graph: Solver.build_graph_for_command(context, command, initial_input)
    }
  end

  def apply_to_context(requirements, _exec_fn) when map_size(requirements.graph.nodes) == 0 do
    requirements.context
  end

  def apply_to_context(requirements, exec_fn) do
    context = requirements.context
    graph = requirements.graph

    sorted_nodes =
      graph
      |> CommandGraph.link_producers_of_required_entities(context)
      |> CommandGraph.deprioritize_nodes_that_delete_entities_or_remove_traits(context)
      |> CommandGraph.topologically_sorted_nodes()

    sorted_nodes
    |> Enum.reduce(context, fn node, context ->
      try do
        args = CommandGraph.Node.resolved_args(node)
        exec_fn.(context, node.name, args)
      rescue
        e in SeedFactory.ExecError ->
          execution_plan = build_execution_plan(sorted_nodes, context, node.name)
          reraise %{e | execution_plan: execution_plan}, __STACKTRACE__
      end
    end)
  end

  defp build_execution_plan(sorted_nodes, context, failed) do
    %{commands: completed} = context.__seed_factory_meta__.current_execution

    Enum.map(sorted_nodes, fn node ->
      cond do
        node.name == failed -> {node.name, :failed}
        node.name in completed -> {node.name, :completed}
        true -> {node.name, :pending}
      end
    end)
  end

  def delete_explicitly_requested_commands(%__MODULE__{} = requirements) do
    %{requirements | graph: CommandGraph.delete_explicitly_requested_nodes(requirements.graph)}
  end
end
