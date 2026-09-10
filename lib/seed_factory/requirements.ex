defmodule SeedFactory.Requirements do
  @moduledoc false

  # The planning core behind produce, pre_produce, exec and pre_exec. A request
  # becomes a plan in four stages:
  #
  #   1. `CandidateGraph` collects everything the request may need into an
  #      AND/OR graph, recording context-dependent facts without resolving;
  #   2. `Solver` searches that graph for a consistent plan, deterministically,
  #      and materializes it into a `CommandGraph`;
  #   3. `apply_to_context/2` fixes the arguments of every step before anything
  #      runs, and `TraitDelivery` predicts with them that every requested
  #      trait survives the plan;
  #   4. the steps run in topological order with those arguments.

  alias SeedFactory.Context
  alias SeedFactory.Params
  alias SeedFactory.Requirements.CommandGraph
  alias SeedFactory.Requirements.Solver
  alias SeedFactory.Requirements.TraitDelivery

  # `requested` lists the `{entity, trait_names}` pairs the execution must
  # deliver at the end of the plan; the parameters of the steps add what they
  # need when they run. pre_produce knowingly withholds the requested
  # entities, so it requests nothing here.
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
  # delivery of the required traits be predicted before each step, for the
  # traits whose verdict is still open.
  def apply_to_context(requirements, exec_fn) do
    context = requirements.context
    graph = requirements.graph

    sorted_nodes =
      graph
      |> CommandGraph.link_producers_of_required_entities(context)
      |> CommandGraph.topologically_sorted_nodes()

    steps = Enum.map(sorted_nodes, fn node -> {node.name, step_args(context, node)} end)
    required = trait_requirements(requirements.requested, context, steps)

    {context, _open} =
      steps
      |> Enum.with_index()
      |> Enum.reduce({context, required}, fn {{command_name, args}, index}, {context, open} ->
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

  # The traits of the request, read at the end of the plan, and the traits the
  # parameters of every step ask for, read when the step runs.
  defp trait_requirements(requested, context, steps) do
    request = Enum.map(requested, fn {entity, trait_names} -> {entity, trait_names, nil} end)

    consumed =
      for {command_name, _args} <- steps,
          {entity, trait_names} <- Context.fetch_command!(context, command_name).required_entities,
          MapSet.size(trait_names) > 0,
          do: {entity, MapSet.to_list(trait_names), command_name}

    request ++ consumed
  end

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
