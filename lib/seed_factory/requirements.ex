defmodule SeedFactory.Requirements do
  @moduledoc false

  alias SeedFactory.Context
  alias SeedFactory.Params
  alias SeedFactory.Requirements.CommandGraph
  alias SeedFactory.Requirements.Solver
  alias SeedFactory.Requirements.TraitDelivery

  # `requested` lists the `{entity, trait_names}` pairs the execution must
  # deliver. pre_produce knowingly withholds the requested entities, so it
  # requests nothing here.
  @enforce_keys [:context, :graph, :requested]
  defstruct [:context, :graph, :requested]

  def build(context, entities_with_trait_names) do
    {graph, requested} = Solver.build_graph(context, entities_with_trait_names)
    %__MODULE__{context: context, graph: graph, requested: requested}
  end

  def build_for_pre_produce(context, entities_with_trait_names) do
    {graph, _requested} = Solver.build_graph_for_pre_produce(context, entities_with_trait_names)
    %__MODULE__{context: context, graph: graph, requested: []}
  end

  def build_for_command(context, command, initial_input) do
    {graph, requested} = Solver.build_graph_for_command(context, command, initial_input)
    %__MODULE__{context: context, graph: graph, requested: requested}
  end

  def apply_to_context(requirements, _exec_fn) when map_size(requirements.graph.nodes) == 0 do
    requirements.context
  end

  # The args of every step are fixed before anything runs: the generators are
  # called here, once, and the execution reuses the values. That lets the
  # delivery of the requested traits be predicted before each step, for the
  # traits whose verdict is still open.
  def apply_to_context(requirements, exec_fn) do
    context = requirements.context
    graph = requirements.graph

    sorted_nodes =
      graph
      |> CommandGraph.link_producers_of_required_entities(context)
      |> CommandGraph.deprioritize_nodes_that_delete_entities_or_remove_traits(context)
      |> CommandGraph.topologically_sorted_nodes()

    steps = Enum.map(sorted_nodes, fn node -> {node.name, step_args(context, node)} end)

    {context, _open} =
      steps
      |> Enum.with_index()
      |> Enum.reduce({context, requirements.requested}, fn {{command_name, args}, index},
                                                           {context, open} ->
        open = predict_open(open, context, Enum.drop(steps, index))

        try do
          {exec_fn.(context, command_name, args), open}
        rescue
          e in SeedFactory.ExecError ->
            execution_plan = build_execution_plan(sorted_nodes, context, command_name)
            reraise %{e | execution_plan: execution_plan}, __STACKTRACE__
        end
      end)

    context
  end

  defp predict_open([], _context, _steps), do: []
  defp predict_open(open, context, steps), do: TraitDelivery.check!(context, steps, open)

  defp step_args(context, node) do
    params = Context.fetch_command!(context, node.name).params
    Params.generate_missing(params, CommandGraph.Node.resolved_args(node))
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
