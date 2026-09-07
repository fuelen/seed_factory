defmodule SeedFactory.Requirements.CandidateGraph do
  @moduledoc false

  # The AND/OR graph of everything the request may need, collected eagerly and
  # without any resolution. Every fact here depends on the context, the schema
  # and the request only, so the solver can read it as plain data:
  #
  #   * an entity node lists the commands able to produce it, once in
  #     declaration order and once with the commands preferred by the requested
  #     traits first;
  #   * a command node lists its parameter demands, each with the outcome of
  #     the context checks (restrictions, consumed traits, trail mismatch);
  #   * a trait node lists the declarations of a trait name for an entity and
  #     what the trail already says about them.
  #
  # Errors found while collecting are recorded on the node that owns them
  # instead of being raised: whether they matter depends on the plan.

  alias SeedFactory.Context
  alias SeedFactory.Requirements.Restrictions

  defmodule EntityNode do
    @moduledoc false
    defstruct [:name, :in_context?, :candidates, :preferred_candidates, :traits_by_command]
  end

  defmodule ParamDemand do
    @moduledoc false
    # status: :ok | {:error, exception}
    defstruct [:entity, :trait_names, :status]
  end

  defmodule CommandNode do
    @moduledoc false
    defstruct [:name, :params, :produces, :deletes]
  end

  defmodule Declaration do
    @moduledoc false
    # prerequisite: nil | {:one, trait_name} | {:any, [trait_name]}
    defstruct [:trait, :command, :prerequisite]
  end

  defmodule TraitNode do
    @moduledoc false
    # status: :continue | :satisfied | {:error, exception}
    defstruct [:entity, :name, :status, :declarations]
  end

  defstruct context: nil,
            restrictions: nil,
            request: [],
            entities: %{},
            commands: %{},
            traits: %{},
            deleters_by_entity: %{}

  @doc """
  Collects the graph reachable from the top-level demands.

  `demands` is a list of `{entity_name, trait_names}` in request order, or
  `{:command, command, initial_input}` for the dependencies of a single command.
  """
  def new(context, restrictions, demands) do
    graph = %__MODULE__{
      context: context,
      restrictions: restrictions,
      deleters_by_entity: deleters_by_entity(context)
    }

    request = Enum.flat_map(demands, &top_level_params(&1, graph))

    graph = %{graph | request: request}

    Enum.reduce(request, graph, fn param, graph ->
      collect_param_demands(graph, [{param.entity, param.trait_names}])
    end)
  end

  # A top-level request behaves like the parameter list of a virtual command
  # nobody executes: the demands of an explicit request carry `nil` as the
  # demander, exactly like today.
  defp top_level_params({:command, command, initial_input}, graph) do
    command
    |> extract_parameter_requirements(initial_input)
    |> Enum.map(fn {entity, trait_names} ->
      build_param_demand(graph, entity, Enum.uniq(trait_names), nil)
    end)
  end

  defp top_level_params({entity, trait_names}, graph) do
    [build_param_demand(graph, entity, Enum.uniq(trait_names), nil)]
  end

  defp deleters_by_entity(context) do
    context.__seed_factory_meta__.commands
    |> Enum.flat_map(fn {name, command} ->
      Enum.map(command.deleting_instructions, &{&1.entity, name})
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp collect_param_demands(graph, params) do
    Enum.reduce(params, graph, fn {entity, trait_names}, graph ->
      graph
      |> collect_entity(entity)
      |> collect_traits(entity, trait_names)
    end)
  end

  defp collect_entity(graph, entity) do
    if Map.has_key?(graph.entities, entity) do
      graph
    else
      node = build_entity_node(graph, entity)
      graph = %{graph | entities: Map.put(graph.entities, entity, node)}

      Enum.reduce(node.candidates, graph, &collect_command(&2, &1))
    end
  end

  defp build_entity_node(graph, entity) do
    context = graph.context

    if Context.entity_exists?(context, entity) do
      %EntityNode{
        name: entity,
        in_context?: true,
        candidates: [],
        preferred_candidates: [],
        traits_by_command: %{}
      }
    else
      {preferred, traits} =
        Restrictions.command_names_and_traits_for_entity(graph.restrictions, context, entity)

      all = Context.fetch_command_names_by_entity!(context, entity)

      %EntityNode{
        name: entity,
        in_context?: false,
        candidates: reject_commands_that_would_duplicate_entity(all, context, entity),
        preferred_candidates:
          reject_commands_that_would_duplicate_entity(preferred, context, entity),
        traits_by_command: Enum.group_by(traits, & &1.exec_step.command_name)
      }
    end
  end

  defp collect_command(graph, command_name) do
    if Map.has_key?(graph.commands, command_name) do
      graph
    else
      command = Context.fetch_command!(graph.context, command_name)

      params =
        command
        |> extract_parameter_requirements(%{})
        |> Enum.map(fn {entity, trait_names} ->
          build_param_demand(graph, entity, Enum.uniq(trait_names), command_name)
        end)

      node = %CommandNode{
        name: command_name,
        params: params,
        produces: Enum.map(command.producing_instructions, & &1.entity),
        deletes: Enum.map(command.deleting_instructions, & &1.entity)
      }

      graph = %{graph | commands: Map.put(graph.commands, command_name, node)}

      collect_param_demands(graph, Enum.map(params, &{&1.entity, &1.trait_names}))
    end
  end

  defp extract_parameter_requirements(command, initial_input) do
    extract_parameter_requirements(command.params, %{}, initial_input)
  end

  defp extract_parameter_requirements(params, acc, initial_input) do
    Enum.reduce(params, acc, fn {key, parameter}, acc ->
      case parameter.type do
        :container ->
          # Params.prepare_args reads the container input nested under the
          # container key, so the coverage check has to look there too.
          nested_input = Map.new(Map.get(initial_input, key, %{}))
          extract_parameter_requirements(parameter.params, acc, nested_input)

        :entity ->
          if Map.has_key?(initial_input, key) do
            acc
          else
            trait_names = parameter.with_traits || []
            Map.update(acc, parameter.entity, trait_names, &(trait_names ++ &1))
          end

        _ ->
          acc
      end
    end)
  end

  defp build_param_demand(graph, entity, trait_names, required_by) do
    %ParamDemand{
      entity: entity,
      trait_names: trait_names,
      status: check_param(graph, entity, trait_names, required_by)
    }
  end

  # Mirrors the context checks of the collector for one demand. The result is
  # stored, not raised: a failing demand only kills its own command as a
  # candidate while another candidate can take over.
  defp check_param(_graph, _entity, [], _required_by), do: :ok

  defp check_param(graph, entity, trait_names, required_by) do
    context = graph.context
    binding_name = Context.binding_name(context, entity)

    with :ok <-
           Restrictions.check_not_restricted(
             graph.restrictions,
             entity,
             binding_name,
             absent_trait_names(context, entity, trait_names),
             required_by
           ),
         :ok <- check_consumed(graph, entity, trait_names) do
      :ok
    end
  end

  defp absent_trait_names(context, entity, trait_names) do
    binding_name = Context.binding_name(context, entity)

    if Map.has_key?(context, binding_name) do
      trait_names -- Context.current_trait_names(context, binding_name)
    else
      trait_names
    end
  end

  defp check_consumed(graph, entity, trait_names) do
    context = graph.context
    binding_name = Context.binding_name(context, entity)

    if Map.has_key?(context, binding_name) do
      case absent_trait_names(context, entity, trait_names) do
        [] ->
          :ok

        absent ->
          %{by_name: traits_by_name} = Context.fetch_traits!(context, entity)
          Restrictions.check_traits_not_consumed(context, entity, absent, traits_by_name)
      end
    else
      :ok
    end
  end

  defp collect_traits(graph, _entity, []), do: graph

  defp collect_traits(graph, entity, trait_names) do
    absent = absent_trait_names(graph.context, entity, trait_names)
    Enum.reduce(absent, graph, &collect_trait(&2, entity, &1))
  end

  defp collect_trait(graph, entity, trait_name) do
    if Map.has_key?(graph.traits, {entity, trait_name}) do
      graph
    else
      node = build_trait_node(graph, entity, trait_name)
      graph = %{graph | traits: Map.put(graph.traits, {entity, trait_name}, node)}

      Enum.reduce(node.declarations, graph, fn declaration, graph ->
        graph = collect_command(graph, declaration.command)

        case declaration.prerequisite do
          nil -> graph
          {:one, name} -> collect_trait(graph, entity, name)
          {:any, names} -> Enum.reduce(names, graph, &collect_trait(&2, entity, &1))
        end
      end)
    end
  end

  defp build_trait_node(graph, entity, trait_name) do
    context = graph.context
    %{by_name: traits_by_name} = Context.fetch_traits!(context, entity)

    # Requested trait names were validated by Restrictions.new and with_traits
    # references are validated at compile time, so the name is always there.
    traits = Map.fetch!(traits_by_name, trait_name)

    case trail_map(graph, entity) do
      {:error, exception} ->
        %TraitNode{
          entity: entity,
          name: trait_name,
          status: {:error, exception},
          declarations: []
        }

      {:ok, trail_map} ->
        status = trail_status(traits, trail_map)

        declarations =
          Enum.map(traits, fn trait ->
            %Declaration{
              trait: trait,
              command: trait.exec_step.command_name,
              prerequisite: prerequisite(trait, traits_by_name, trail_map)
            }
          end)

        %TraitNode{entity: entity, name: trait_name, status: status, declarations: declarations}
    end
  end

  # An entity that can have traits and sits in the context without a trail was
  # put there by hand. The error is kept on the node so it is raised only when
  # the plan really needs the trait.
  defp trail_map(graph, entity) do
    context = graph.context
    binding_name = Context.binding_name(context, entity)

    if Map.has_key?(context, binding_name) do
      case Context.fetch_trail(context, binding_name) do
        nil ->
          {:error,
           %RuntimeError{
             message: """
             Can't find trail for #{inspect(binding_name)} entity.
             Please don't put entities that can have traits manually in the context.
             """
           }}

        trail ->
          {:ok, SeedFactory.Trail.to_map(trail)}
      end
    else
      {:ok, %{}}
    end
  end

  # The trait may be declared on several commands and more than one of them may
  # sit in the trail, so a mismatch is reported only when no executed
  # declaration added the trait.
  defp trail_status(traits, trail_map) do
    executed =
      Enum.flat_map(traits, fn trait ->
        case trail_map[trait.exec_step.command_name] do
          nil -> []
          data -> [{trait, data}]
        end
      end)

    cond do
      executed == [] ->
        :continue

      Enum.any?(executed, fn {trait, %{added: added}} -> trait.name in added end) ->
        :satisfied

      true ->
        {:mismatch, Enum.map(executed, fn {trait, %{added: added}} -> {trait, added} end)}
    end
  end

  defp prerequisite(%{from: nil}, _traits_by_name, _trail_map), do: nil

  defp prerequisite(%{from: from}, _traits_by_name, _trail_map) when is_atom(from) do
    {:one, from}
  end

  defp prerequisite(%{from: from_any_of}, traits_by_name, trail_map) when is_list(from_any_of) do
    satisfied? =
      Enum.any?(from_any_of, fn from ->
        Enum.any?(traits_by_name[from], fn trait ->
          case trail_map[trait.exec_step.command_name] do
            nil -> false
            %{added: added} -> trait.name in added
          end
        end)
      end)

    if satisfied? do
      nil
    else
      {:any, from_any_of}
    end
  end

  defp reject_commands_that_would_duplicate_entity(command_names, context, target_entity) do
    case Enum.reject(command_names, &command_would_duplicate_entity?(&1, context, target_entity)) do
      [] -> command_names
      filtered -> filtered
    end
  end

  defp command_would_duplicate_entity?(command_name, context, target_entity) do
    command = Context.fetch_command!(context, command_name)

    Enum.any?(command.producing_instructions, fn instruction ->
      instruction.entity != target_entity and Context.entity_exists?(context, instruction.entity)
    end)
  end
end
