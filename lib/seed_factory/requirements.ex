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

    graph
    |> CommandGraph.deprioritize_nodes_that_delete_entities_or_remove_traits(context)
    |> CommandGraph.topologically_sorted_nodes()
    |> Enum.reduce(context, fn node, context ->
      args = CommandGraph.Node.resolved_args(node)
      exec_fn.(context, node.name, args)
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
