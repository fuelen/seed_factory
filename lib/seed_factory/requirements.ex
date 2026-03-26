defmodule SeedFactory.Requirements do
  @moduledoc false

  alias SeedFactory.Requirements.CommandGraph
  alias SeedFactory.Requirements.Restrictions

  @enforce_keys [:context, :restrictions, :graph]
  defstruct [:context, :restrictions, :graph]

  def new(context, entities_with_trait_names) do
    restrictions = Restrictions.new(context, entities_with_trait_names)
    graph = CommandGraph.new()
    %__MODULE__{context: context, restrictions: restrictions, graph: graph}
  end

  def apply_to_context(requirements, _exec_fn) when map_size(requirements.graph.nodes) == 0 do
    requirements.context
  end

  def apply_to_context(requirements, exec_fn) do
    context = requirements.context
    graph = requirements.graph

    sorted_nodes =
      graph
      |> CommandGraph.deprioritize_nodes_that_delete_entities_or_remove_traits(context)
      |> CommandGraph.topologically_sorted_nodes()

    sorted_nodes
    |> Enum.reduce(context, fn node, context ->
      try do
        args = CommandGraph.Node.resolved_args(node)
        exec_fn.(context, node.name, args)
      rescue
        e in SeedFactory.ExecError ->
          completed = current_execution_commands(context)
          execution_plan = build_execution_plan(sorted_nodes, completed, node.name)
          reraise %{e | execution_plan: execution_plan}, __STACKTRACE__
      end
    end)
  end

  defp current_execution_commands(context) do
    case context.__seed_factory_meta__.current_execution do
      %{commands: commands} -> MapSet.new(commands)
      nil -> MapSet.new()
    end
  end

  defp build_execution_plan(sorted_nodes, completed, failed) do
    Enum.map(sorted_nodes, fn node ->
      cond do
        node.name == failed -> {node.name, :failed}
        MapSet.member?(completed, node.name) -> {node.name, :completed}
        true -> {node.name, :pending}
      end
    end)
  end

  def resolve_conflicts(%__MODULE__{} = requirements) do
    %{requirements | graph: CommandGraph.resolve_conflicts(requirements.graph)}
  end

  def delete_explicitly_requested_commands(%__MODULE__{} = requirements) do
    %{requirements | graph: CommandGraph.delete_explicitly_requested_nodes(requirements.graph)}
  end

  def unwrap!({:ok, requirements}), do: requirements
  def unwrap!({:error, exception}), do: raise(exception)

  # Delegation to Collector

  defdelegate for_command(requirements, command, initial_input, required_by),
    to: SeedFactory.Requirements.Collector

  defdelegate for_entities_with_trait_names(requirements, entities_with_trait_names, required_by),
    to: SeedFactory.Requirements.Collector
end
