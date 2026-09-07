defmodule SeedFactory.Requirements.Solver do
  @moduledoc false

  # Searches the candidate graph for a consistent plan: one command per active
  # demand such that no two chosen commands produce a common entity (unless a
  # chosen deleter runs between them; an entity already sitting in the context
  # counts as produced before the plan starts), the chosen set is orderable,
  # and every demand of a chosen command is satisfied in turn.
  #
  # The search is depth-first with chronological backtracking. The order of
  # decisions is the determinism spec:
  #
  #   * demands live on a stack, the newest first, mirroring the LIFO order of
  #     the conflict groups the previous core resolved;
  #   * a demand with a single viable option is applied before any decision
  #     (unit propagation);
  #   * an already-chosen command satisfying a demand is reused, never
  #     duplicated;
  #   * among real decisions, the first option that does not leave another
  #     demand without viable candidates wins (the safety lookahead of the
  #     previous core), then any safe option, then the first option;
  #   * a trait demand orders its declarations by how many demanded entities
  #     the exec command produces, so related entities come from the same
  #     command, then by declaration order;
  #   * entity demands keep the candidate order of the candidate graph:
  #     commands preferred by requested traits first, then declaration order.
  #
  # The contract of a request is that every requested entity sits in the final
  # context: a command deleting one is never part of the plan, and a request
  # that cannot be satisfied without such a command fails loudly.
  #
  # pre_produce works in its own mode with one difference from produce: a
  # command chosen for a top-level demand is a phantom, and so is any chosen
  # command producing a requested entity (pre_produce prunes by
  # produced-entity membership, so a real one would sneak the entity into the
  # context). pre_produce deletes phantoms before execution, so they join the
  # plan only to have their dependencies planned. Their produce and delete
  # effects never happen: a phantom registers no producers, cannot conflict
  # with other producers and cannot legalize an interleave. Everything else,
  # the protection of requested entities included, works exactly as in
  # produce. The deletion cascade keeps the remainder consistent: every
  # command that demanded a phantom's output dies with it.
  #
  # The solve runs in up to two passes. The second allows cyclic plans and
  # exists only for diagnosis: its solution is materialized so the downstream
  # passes report it — usually the topological sort with the cycle, or the
  # link_producers safety net when a command supplied its own parameter. When
  # both passes fail, the first dead end of the strict pass is raised.

  alias SeedFactory.Requirements.CandidateGraph
  alias SeedFactory.Requirements.CommandGraph
  alias SeedFactory.Requirements.CommandGraph.Node
  alias SeedFactory.Requirements.Restrictions

  # The virtual first producer of an entity already sitting in the context:
  # it joins interleave sequences in the leaf check but is not a command, so
  # it never carries an edge and never reaches an error message.
  @context_instance :__context_instance__

  def build_graph(context, entities_with_trait_names) do
    restrictions = Restrictions.new(context, entities_with_trait_names)
    candidate_graph = CandidateGraph.new(context, restrictions, entities_with_trait_names)
    solve_and_materialize(candidate_graph, :produce)
  end

  def build_graph_for_pre_produce(context, entities_with_trait_names) do
    restrictions = Restrictions.new(context, entities_with_trait_names)
    candidate_graph = CandidateGraph.new(context, restrictions, entities_with_trait_names)
    solve_and_materialize(candidate_graph, :pre_produce)
  end

  def build_graph_for_command(context, command, initial_input) do
    restrictions = Restrictions.new(context, [])

    candidate_graph =
      CandidateGraph.new(context, restrictions, [{:command, command, initial_input}])

    solve_and_materialize(candidate_graph, :produce)
  end

  defp solve_and_materialize(candidate_graph, mode) do
    passes = [%{strict_cycles?: true}, %{strict_cycles?: false}]

    run_passes(passes, candidate_graph, mode, nil)
  end

  defp run_passes([pass | rest], candidate_graph, mode, strict_failure) do
    state = initial_state(candidate_graph, mode, pass)

    case solve(state) do
      {:ok, solution} ->
        # A solution found by the relaxed pass carries the cycle the strict
        # passes refused, so the topological sort reports it downstream.
        to_command_graph(solution)

      {:fail, failure} ->
        strict_failure =
          if pass.strict_cycles? do
            strict_failure || failure
          else
            strict_failure
          end

        case rest do
          [] ->
            raise (strict_failure || failure).exception

          rest ->
            run_passes(rest, candidate_graph, mode, strict_failure)
        end
    end
  end

  defp initial_state(candidate_graph, mode, pass) do
    pre_produce? = mode == :pre_produce

    state = %{
      candidate_graph: candidate_graph,
      pre_produce?: pre_produce?,
      chosen: MapSet.new(),
      excluded: MapSet.new(),
      phantoms: MapSet.new(),
      edges: [],
      requires: %{},
      producers: %{},
      extra_edges: [],
      stack: [],
      strict_cycles?: pass.strict_cycles?,
      protected: MapSet.new(candidate_graph.request, & &1.entity)
    }

    push_params(state, candidate_graph.request, nil)
  end

  # The search

  defp solve(state) do
    case next_step(state) do
      :done ->
        leaf_check(state)

      {:fail, failure} ->
        {:fail, failure}

      {:drop, demand} ->
        solve(%{state | stack: List.delete(state.stack, demand)})

      {:decide, demand, options} ->
        try_options(state, demand, options, [])
    end
  end

  defp try_options(state, demand, [option | rest], failures) do
    new_state = apply_option(state, demand, option)

    case solve(new_state) do
      {:ok, _} = ok -> ok
      {:fail, failure} -> try_options(state, demand, rest, [{option, failure} | failures])
    end
  end

  defp try_options(state, demand, [], failures) do
    {:fail, aggregate_failures(state, demand, Enum.reverse(failures))}
  end

  # The stack keeps demands in decision order: newer pushes first, the trait
  # demands of one request entry before its entity demand, sibling entries in
  # request (or parameter) order. Traits therefore commit greedily in request
  # order and a later conflicting trait fails on its own turn.
  defp next_step(state) do
    results = Enum.map(state.stack, fn demand -> {demand, viable_options(state, demand)} end)

    cond do
      satisfied = Enum.find(results, fn {_, result} -> result == :satisfied end) ->
        {:drop, elem(satisfied, 0)}

      zero = Enum.find(results, fn {_, result} -> match?({:zero, _}, result) end) ->
        {_, {:zero, failure}} = zero
        {:fail, failure}

      unit = Enum.find(results, fn {_, result} -> match?({:options, [_]}, result) end) ->
        {demand, {:options, [option]}} = unit
        {:decide, demand, [option]}

      results == [] ->
        :done

      true ->
        pick_decision(state, for({demand, {:options, options}} <- results, do: {demand, options}))
    end
  end

  defp pick_decision(state, decisions) do
    {demand, options} =
      Enum.find(decisions, fn {demand, [first | _]} -> safe?(state, demand, first) end) ||
        Enum.find_value(decisions, fn {demand, options} ->
          case Enum.find(options, &safe?(state, demand, &1)) do
            nil -> nil
            option -> {demand, [option | List.delete(options, option)]}
          end
        end) ||
        hd(decisions)

    {:decide, demand, options}
  end

  # Viability

  defp viable_options(_state, {:failed, exception}) do
    {:zero, %{kind: :other, exception: exception}}
  end

  defp viable_options(state, {:entity, entity, demander, preferred?} = demand) do
    node = Map.fetch!(state.candidate_graph.entities, entity)

    if node.in_context? do
      :satisfied
    else
      candidates =
        if preferred? do
          node.preferred_candidates
        else
          node.candidates
        end

      reuse =
        Enum.find(candidates, fn cmd ->
          MapSet.member?(state.chosen, cmd) and cycle_ok?(state, demander, cmd)
        end)

      if reuse do
        {:options, [{:reuse, reuse, edge_traits(node, preferred?, reuse)}]}
      else
        viable =
          for cmd <- candidates,
              not MapSet.member?(state.chosen, cmd),
              not MapSet.member?(state.excluded, cmd),
              command_collection_failure(state.candidate_graph, cmd) == nil,
              phantom?(state, demander, cmd) or
                (not produce_conflict?(state, cmd) and
                   not self_consuming_producer?(state, cmd)),
              not deletes_protected?(state, cmd),
              cycle_ok?(state, demander, cmd) do
            {:choose, cmd, edge_traits(node, preferred?, cmd)}
          end

        case viable do
          [] -> {:zero, entity_failure(state, demand, candidates)}
          viable -> {:options, viable}
        end
      end
    end
  end

  defp viable_options(state, {:trait, entity, name, demander}) do
    node = Map.fetch!(state.candidate_graph.traits, {entity, name})

    case node.status do
      :satisfied ->
        :satisfied

      {:mismatch, executed} ->
        {:zero, trait_failure(entity, name, demander, {:trait_mismatch, executed, demander})}

      {:error, exception} ->
        {:zero, %{kind: :other, exception: exception}}

      :continue ->
        reuse =
          Enum.find(node.declarations, fn decl ->
            decl.command != demander and MapSet.member?(state.chosen, decl.command) and
              cycle_ok?(state, demander, decl.command)
          end)

        if reuse do
          {:options, [{:decl, reuse, :reuse}]}
        else
          viable =
            for decl <- node.declarations,
                decl.command != demander,
                not MapSet.member?(state.chosen, decl.command),
                not MapSet.member?(state.excluded, decl.command),
                command_collection_failure(state.candidate_graph, decl.command) == nil,
                phantom?(state, demander, decl.command) or
                  (not produce_conflict?(state, decl.command) and
                     not self_consuming_producer?(state, decl.command)),
                not deletes_protected?(state, decl.command),
                cycle_ok?(state, demander, decl.command) do
              {:decl, decl, :choose}
            end

          case order_declarations(state, viable) do
            [] ->
              rejections = declaration_rejections(state, node, demander)
              {:zero, trait_failure(entity, name, demander, {:commands_rejected, rejections})}

            viable ->
              {:options, viable}
          end
        end
    end
  end

  defp viable_options(state, {:any, entity, options, demander}) do
    usable =
      Enum.filter(options, fn name ->
        Map.fetch!(state.candidate_graph.traits, {entity, name}).status in [:continue, :satisfied]
      end)

    case usable do
      [] ->
        # Every option is dead at collection time: report the first one, as it
        # represents the preferred route.
        first = hd(options)
        {:zero, dead_any_option_failure(state, entity, first, demander)}

      usable ->
        {:options, Enum.map(usable, &{:opt, &1})}
    end
  end

  # A missing trail invalidates every trait node of the entity at once, so a
  # dead option here can only be a trail mismatch.
  defp dead_any_option_failure(state, entity, name, demander) do
    {:mismatch, executed} = Map.fetch!(state.candidate_graph.traits, {entity, name}).status
    trait_failure(entity, name, demander, {:trait_mismatch, executed, demander})
  end

  # Related entities come from the same command whenever possible: among
  # several creation routes for one trait, the exec producing more demanded
  # entities wins, and ties keep the declaration order. As soon as a transition
  # route is involved, the declaration order alone decides.
  defp order_declarations(_state, []), do: []
  defp order_declarations(_state, [_] = options), do: options

  defp order_declarations(state, options) do
    all_creations? =
      Enum.all?(options, fn {:decl, decl, _mode} ->
        decl.trait.entity in Map.fetch!(state.candidate_graph.commands, decl.command).produces
      end)

    if all_creations? do
      demanded = demanded_entities(state)

      Enum.sort_by(options, fn {:decl, decl, _mode} ->
        produces = Map.fetch!(state.candidate_graph.commands, decl.command).produces
        -Enum.count(produces, &MapSet.member?(demanded, &1))
      end)
    else
      options
    end
  end

  defp demanded_entities(state) do
    hard = for {:entity, entity, _, _} <- state.stack, do: entity
    soft = for {:entity, entity, _, _} <- soft_demands(state), do: entity

    MapSet.new(hard ++ soft)
  end

  defp edge_traits(node, preferred?, cmd) do
    if preferred? do
      Map.get(node.traits_by_command, cmd, [])
    else
      []
    end
  end

  defp command_collection_failure(candidate_graph, cmd) do
    candidate_graph.commands
    |> Map.fetch!(cmd)
    |> Map.fetch!(:params)
    |> Enum.find_value(fn
      %{status: {:error, exception}} -> exception
      _ -> nil
    end)
  end

  # An entity already sitting in the context counts as produced before the
  # plan starts, so a command re-producing it needs a deleter just like a
  # second producer does.
  defp produce_conflict?(state, cmd) do
    produce_conflict_reason(state, cmd) != nil
  end

  defp produce_conflict_reason(state, cmd) do
    state.candidate_graph.commands
    |> Map.fetch!(cmd)
    |> Map.fetch!(:produces)
    |> Enum.find_value(fn entity ->
      others = Map.get(state.producers, entity, []) -- [cmd]

      cond do
        reachable_deleters(state, entity) != [] -> nil
        others != [] -> {:produce_conflict, entity, hd(others)}
        context_instance?(state, entity) -> {:would_duplicate, entity}
        true -> nil
      end
    end)
  end

  defp context_instance?(state, entity) do
    SeedFactory.Context.entity_exists?(state.candidate_graph.context, entity)
  end

  # A command producing an entity it also consumes can never run as a plan
  # node: its parameter needs a live instance, its produce needs none, and the
  # DSL forbids deleting the same entity in the same command. Such a command
  # is executable only through exec with the parameter covered by the initial
  # input. A phantom never executes, so the check does not apply to it.
  defp self_consuming_producer?(state, cmd) do
    self_consumed_entity(state, cmd) != nil
  end

  defp self_consumed_entity(state, cmd) do
    node = Map.fetch!(state.candidate_graph.commands, cmd)
    param_entities = MapSet.new(node.params, & &1.entity)

    Enum.find(node.produces, &MapSet.member?(param_entities, &1))
  end

  # Rebuilds, on the failure path only, why a candidate did not pass the
  # viability filters. Mirrors their order; nil for a viable candidate (one
  # that was tried and failed deeper in the search).
  defp rejection_reason(state, demander, cmd) do
    cond do
      MapSet.member?(state.chosen, cmd) ->
        {:cycle, demander}

      MapSet.member?(state.excluded, cmd) ->
        :lost_trait_resolution

      exception = command_collection_failure(state.candidate_graph, cmd) ->
        {:collection, exception}

      reason = viable_conflict_reason(state, demander, cmd) ->
        reason

      entity = deleted_protected_entity(state, cmd) ->
        {:deletes_requested, entity}

      # The only filter left is the cycle check. An unchosen candidate carries
      # no requires edges, so it can fail that check only in exotic shapes the
      # suite cannot construct - the arm mirrors the filter as a net.
      true ->
        {:cycle, demander}
    end
  end

  defp viable_conflict_reason(state, demander, cmd) do
    if phantom?(state, demander, cmd) do
      nil
    else
      case produce_conflict_reason(state, cmd) do
        nil ->
          case self_consumed_entity(state, cmd) do
            nil -> nil
            entity -> {:self_consuming, entity}
          end

        reason ->
          reason
      end
    end
  end

  defp deleted_protected_entity(state, cmd) do
    state.candidate_graph.commands
    |> Map.fetch!(cmd)
    |> Map.fetch!(:deletes)
    |> Enum.find(&MapSet.member?(state.protected, &1))
  end

  # Only deleters that can end up in the plan legalize a second producer: they
  # must have been collected as candidates and must not delete a protected
  # entity (such a command is never chosen).
  defp reachable_deleters(state, entity) do
    state.candidate_graph.deleters_by_entity
    |> Map.get(entity, [])
    |> Enum.filter(fn cmd ->
      Map.has_key?(state.candidate_graph.commands, cmd) and not deletes_protected?(state, cmd)
    end)
  end

  # A command deleting a requested entity can never be part of the plan:
  # produce guarantees the entity sits in the final context, pre_produce
  # guarantees a request never consumes what it names.
  defp deletes_protected?(state, cmd) do
    deleted_protected_entity(state, cmd) != nil
  end

  # In the pre_produce mode a chosen command whose effects must not survive
  # the pruning is a phantom: a candidate of a top-level demand (pre_produce
  # deletes those by definition) and any command producing a requested entity
  # (a real one would sneak the entity into the context, mirroring the v0.8.2
  # pruning by produced-entity membership). A phantom registers no produces,
  # so it cannot conflict with anything.
  defp phantom?(state, demander, cmd) do
    state.pre_produce? and (demander == nil or produces_requested?(state, cmd))
  end

  defp produces_requested?(state, cmd) do
    state.candidate_graph.commands
    |> Map.fetch!(cmd)
    |> Map.fetch!(:produces)
    |> Enum.any?(&MapSet.member?(state.protected, &1))
  end

  defp cycle_ok?(state, demander, cmd) do
    cond do
      not state.strict_cycles? -> true
      demander == nil -> true
      cmd == demander -> false
      true -> not reaches?(state.requires, cmd, demander)
    end
  end

  defp reaches?(requires, from, target) do
    walk_requires([from], requires, target, MapSet.new())
  end

  defp walk_requires([], _requires, _target, _seen), do: false

  defp walk_requires([from | rest], requires, target, seen) do
    deps = Map.get(requires, from, MapSet.new())

    if MapSet.member?(deps, target) do
      true
    else
      new = MapSet.difference(deps, seen)
      walk_requires(MapSet.to_list(new) ++ rest, requires, target, MapSet.union(seen, new))
    end
  end

  # Safety: applying the option must leave every demand that can still matter
  # with at least one viable candidate. Checked demands are the pending hard
  # ones plus the demands of live candidates — commands reachable as viable
  # candidates from the pending demands. Candidates cut off by the choice
  # (losing alternatives, conflicting commands) stop being reachable, so their
  # demands expire exactly like the demands of removed group members today.
  defp safe?(state, item, option) do
    case option do
      {:choose, _cmd, _traits} -> safe_after?(apply_option(state, item, option))
      {:decl, _decl, :choose} -> safe_after?(apply_option(state, item, option))
      _reuse_or_opt -> true
    end
  end

  defp safe_after?(state) do
    not Enum.any?(state.stack ++ soft_demands(state), fn demand ->
      match?({:zero, _}, viable_options(state, demand))
    end)
  end

  defp soft_demands(state) do
    live = reachable_live(state)

    params =
      for cmd <- live,
          param <- Map.fetch!(state.candidate_graph.commands, cmd).params,
          param.status == :ok,
          demand <- param_demands(state.candidate_graph, param, cmd),
          do: demand

    prerequisites =
      for {{entity, _name}, node} <- state.candidate_graph.traits,
          node.status == :continue,
          decl <- node.declarations,
          MapSet.member?(live, decl.command),
          demand <- prerequisite_demands(entity, decl),
          do: demand

    params ++ prerequisites
  end

  defp prerequisite_demands(entity, decl) do
    case decl.prerequisite do
      nil -> []
      {:one, name} -> [{:trait, entity, name, decl.command}]
      {:any, options} -> [{:any, entity, options, decl.command}]
    end
  end

  # Commands reachable as viable candidates from the pending demands. Chosen
  # commands are not included: their demands are already pending.
  defp reachable_live(state) do
    state.stack
    |> Enum.flat_map(&demand_candidates(state, &1))
    |> expand_live(state, MapSet.new())
  end

  defp expand_live([], _state, live), do: live

  defp expand_live([cmd | rest], state, live) do
    if MapSet.member?(live, cmd) do
      expand_live(rest, state, live)
    else
      live = MapSet.put(live, cmd)
      node = Map.fetch!(state.candidate_graph.commands, cmd)

      from_params =
        for param <- node.params,
            param.status == :ok,
            demand <- param_demands(state.candidate_graph, param, cmd),
            candidate <- demand_candidates(state, demand),
            do: candidate

      from_prerequisites =
        for {{entity, _name}, trait_node} <- state.candidate_graph.traits,
            trait_node.status == :continue,
            decl <- trait_node.declarations,
            decl.command == cmd,
            demand <- prerequisite_demands(entity, decl),
            candidate <- demand_candidates(state, demand),
            do: candidate

      expand_live(from_params ++ from_prerequisites ++ rest, state, live)
    end
  end

  # The cheap viability used for reachability: collection failures, conflicts
  # with chosen producers and the protected entities, but no cycle analysis
  # and no phantom awareness (the pre_produce relaxations decide options, not
  # reachability).
  defp demand_candidates(state, {:entity, entity, _demander, _preferred?}) do
    node = Map.fetch!(state.candidate_graph.entities, entity)

    if node.in_context? do
      []
    else
      Enum.filter(node.candidates, &candidate_live?(state, &1))
    end
  end

  defp demand_candidates(state, {:trait, entity, name, demander}) do
    node = Map.fetch!(state.candidate_graph.traits, {entity, name})

    case node.status do
      :continue ->
        for decl <- node.declarations,
            decl.command != demander,
            candidate_live?(state, decl.command),
            do: decl.command

      _ ->
        []
    end
  end

  defp demand_candidates(state, {:any, entity, options, demander}) do
    Enum.flat_map(options, &demand_candidates(state, {:trait, entity, &1, demander}))
  end

  # A failed top-level demand can still sit on the stack while the options of
  # its siblings are computed; the failure fires on its own turn.
  defp demand_candidates(_state, {:failed, _exception}), do: []

  defp candidate_live?(state, cmd) do
    not MapSet.member?(state.chosen, cmd) and
      not MapSet.member?(state.excluded, cmd) and
      command_collection_failure(state.candidate_graph, cmd) == nil and
      not produce_conflict?(state, cmd) and
      not deletes_protected?(state, cmd)
  end

  # The trait demands of one entry go before its entity demand, so the trait
  # choices steer the producer choice and not the other way around.
  defp param_demands(candidate_graph, param, demander) do
    entity = [{:entity, param.entity, demander, param.trait_names == []}]

    traits =
      for name <- param.trait_names,
          Map.has_key?(candidate_graph.traits, {param.entity, name}),
          do: {:trait, param.entity, name, demander}

    traits ++ entity
  end

  # Applying options

  defp apply_option(state, demand, option) do
    state = %{state | stack: List.delete(state.stack, demand)}

    case {demand, option} do
      {{:entity, _entity, demander, _}, {:reuse, cmd, traits}} ->
        add_edge(state, demander, cmd, traits)

      {{:entity, _entity, demander, _}, {:choose, cmd, traits}} ->
        state
        |> choose(cmd, phantom?(state, demander, cmd))
        |> add_edge(demander, cmd, traits)

      {{:trait, entity, name, demander}, {:decl, decl, mode}} ->
        state =
          case mode do
            :choose -> choose(state, decl.command, phantom?(state, demander, decl.command))
            :reuse -> state
          end

        state
        |> exclude_losing_declarations(entity, name, decl)
        |> add_edge(demander, decl.command, [decl.trait])
        |> push_prerequisite(entity, decl)

      {{:any, entity, _options, demander}, {:opt, name}} ->
        push_demands(state, [{:trait, entity, name, demander}])
    end
  end

  # The winner of a trait demand takes the whole plan: the exec commands of the
  # losing declarations are out, exactly like the removed members of a resolved
  # conflict group today. Backtracking brings them back when the winner's
  # subtree fails.
  defp exclude_losing_declarations(state, entity, name, winner) do
    losers =
      state.candidate_graph.traits
      |> Map.fetch!({entity, name})
      |> Map.fetch!(:declarations)
      |> Enum.map(& &1.command)
      |> Enum.reject(fn cmd ->
        cmd == winner.command or MapSet.member?(state.chosen, cmd)
      end)

    %{state | excluded: MapSet.union(state.excluded, MapSet.new(losers))}
  end

  defp choose(state, cmd, phantom?) do
    node = Map.fetch!(state.candidate_graph.commands, cmd)

    state =
      if phantom? do
        # The nil edge marks the phantom as explicitly requested, so the
        # pre_produce pruning removes it and its demanders cascade away.
        state = add_edge(state, nil, cmd, [])
        %{state | phantoms: MapSet.put(state.phantoms, cmd)}
      else
        producers =
          Enum.reduce(node.produces, state.producers, fn entity, acc ->
            Map.update(acc, entity, [cmd], &(&1 ++ [cmd]))
          end)

        %{state | producers: producers}
      end

    state = %{state | chosen: MapSet.put(state.chosen, cmd)}
    push_params(state, node.params, cmd)
  end

  defp add_edge(state, demander, cmd, traits) do
    requires =
      case demander do
        nil -> state.requires
        demander -> Map.update(state.requires, demander, MapSet.new([cmd]), &MapSet.put(&1, cmd))
      end

    %{state | edges: [{demander, cmd, traits} | state.edges], requires: requires}
  end

  defp push_prerequisite(state, entity, decl) do
    push_demands(state, prerequisite_demands(entity, decl))
  end

  defp push_params(state, params, demander) do
    params
    |> Enum.flat_map(&param_demands_or_failure(state.candidate_graph, &1, demander))
    |> then(&push_demands(state, &1))
  end

  defp push_demands(state, demands) do
    %{state | stack: demands ++ state.stack}
  end

  defp param_demands_or_failure(candidate_graph, param, demander) do
    case param.status do
      {:error, exception} -> [{:failed, exception}]
      :ok -> param_demands(candidate_graph, param, demander)
    end
  end

  # Failures

  defp entity_failure(state, {:entity, entity, demander, _}, candidates) do
    collection_failures =
      Enum.map(candidates, &command_collection_failure(state.candidate_graph, &1))

    exception =
      if candidates != [] and Enum.all?(collection_failures) do
        hd(collection_failures)
      else
        SeedFactory.UnproducibleEntityError.exception(
          entity: entity,
          required_by: demander,
          commands: candidates,
          rejections: Enum.map(candidates, &{&1, rejection_reason(state, demander, &1)})
        )
      end

    %{kind: :other, exception: exception}
  end

  # The trait's declarations, each with the reason its exec command was
  # unusable. An exec that was tried and failed deeper carries no viability
  # reason: it failed on its prerequisite, reported separately.
  defp declaration_rejections(state, node, demander, tried_commands \\ []) do
    node.declarations
    |> Enum.map(& &1.command)
    |> Enum.uniq()
    |> Enum.map(fn cmd ->
      cond do
        cmd == demander -> {cmd, :own_trait_demand}
        cmd in tried_commands -> {cmd, :prerequisite_failed}
        true -> {cmd, rejection_reason(state, demander, cmd)}
      end
    end)
  end

  defp trait_failure(entity, name, demander, reason) do
    %{
      kind: :trait,
      entity: entity,
      name: name,
      demander: demander,
      reason: reason,
      exception:
        SeedFactory.TraitResolutionError.exception(
          entity: entity,
          trait: name,
          required_by: demander,
          reason: reason
        )
    }
  end

  defp aggregate_failures(state, {:trait, entity, name, demander}, failures) do
    # A subtree failure unrelated to the declaration itself (a parameter of the
    # exec command, a demand elsewhere in the plan) is the real cause and
    # passes through; only prerequisite failures fold into the trait error.
    unrelated =
      Enum.find_value(failures, fn {{:decl, decl, _mode}, failure} ->
        if prerequisite_failure?(decl, failure) do
          nil
        else
          failure
        end
      end)

    if unrelated do
      unrelated
    else
      # Every tried declaration failed on its own prerequisite.
      prereq_reasons =
        for {{:decl, decl, _mode}, failure} <- failures,
            prerequisite_failure?(decl, failure) do
          {:prerequisite_unsatisfied, name, failure.name, failure.reason}
        end

      tried_commands =
        for {{:decl, decl, _mode}, failure} <- failures,
            prerequisite_failure?(decl, failure),
            do: decl.command

      node = Map.fetch!(state.candidate_graph.traits, {entity, name})
      rejections = declaration_rejections(state, node, demander, tried_commands)
      reason = {:all_traits_failed, [{:commands_rejected, rejections} | prereq_reasons]}

      trait_failure(entity, name, demander, reason)
    end
  end

  defp aggregate_failures(_state, _demand, [{_option, first} | _rest]), do: first

  defp prerequisite_failure?(decl, %{kind: :trait, demander: demander, name: name}) do
    demander == decl.command and
      case decl.prerequisite do
        {:one, prerequisite} -> name == prerequisite
        {:any, options} -> name in options
        nil -> false
      end
  end

  defp prerequisite_failure?(_decl, _failure), do: false

  # The leaf: several chosen commands producing one entity are legal only when
  # every chosen deleter of that entity fits between two of its producers, in
  # an order compatible with the dependencies. An entity already sitting in
  # the context joins as a virtual first producer pinned to the head of the
  # sequence. The sequence chosen for one entity constrains the others, so the
  # entities are ordered by a joint backtracking search. The ordering edges
  # become part of the plan.
  defp leaf_check(state) do
    # A single chosen producer with several chosen deleters has nothing to
    # interleave, but the count check below still has to refuse it.
    multi =
      for {entity, [_ | _] = producers} <- state.producers,
          producers = with_context_instance(state, entity, producers),
          match?([_, _ | _], producers) or several_chosen_deleters?(state, entity),
          do: {entity, producers}

    # A context instance with several chosen deleters and no re-producer is
    # over-deleted: only the first deleter would find it alive.
    producerless =
      for {entity, _deleters} <- state.candidate_graph.deleters_by_entity,
          not Map.has_key?(state.producers, entity),
          context_instance?(state, entity),
          several_chosen_deleters?(state, entity),
          do: {entity, [@context_instance]}

    case order_multi_producers(state, multi ++ producerless, state.extra_edges) do
      {:ok, edges} ->
        {:ok, %{state | extra_edges: edges}}

      {:unorderable, entity, [@context_instance], deleters} ->
        exception =
          SeedFactory.UnproducibleEntityError.exception(
            entity: entity,
            required_by: nil,
            commands: deleters,
            cause: :over_deleted
          )

        {:fail, %{kind: :other, exception: exception}}

      {:unorderable, entity, producers, _deleters} ->
        exception =
          SeedFactory.UnproducibleEntityError.exception(
            entity: entity,
            required_by: nil,
            commands: producers -- [@context_instance],
            cause: :unorderable
          )

        {:fail, %{kind: :other, exception: exception}}
    end
  end

  defp order_multi_producers(_state, [], edges), do: {:ok, edges}

  defp order_multi_producers(state, [{entity, producers} | rest], edges) do
    deleters =
      chosen_deleters(state, Map.get(state.candidate_graph.deleters_by_entity, entity, []))

    unorderable = {:unorderable, entity, producers, deleters}

    case consistent_sequences(state, producers, deleters, edges) do
      [] ->
        unorderable

      sequences ->
        Enum.reduce_while(sequences, unorderable, fn sequence, _failure ->
          case order_multi_producers(
                 state,
                 rest,
                 edges ++ consecutive_edges(sequence, edges, state)
               ) do
            {:ok, _} = ok -> {:halt, ok}
            {:unorderable, _, _, _} = failure -> {:cont, failure}
          end
        end)
    end
  end

  defp chosen_deleters(state, deleters) do
    Enum.filter(deleters, fn cmd ->
      MapSet.member?(state.chosen, cmd) and not MapSet.member?(state.phantoms, cmd)
    end)
  end

  defp several_chosen_deleters?(state, entity) do
    deleters = Map.get(state.candidate_graph.deleters_by_entity, entity, [])
    match?([_, _ | _], chosen_deleters(state, deleters))
  end

  defp with_context_instance(state, entity, producers) do
    if context_instance?(state, entity) do
      [@context_instance | producers]
    else
      producers
    end
  end

  defp consistent_sequences(state, producers, deleters, edges) do
    {head, permutable} =
      case producers do
        [@context_instance | rest] -> {[@context_instance], rest}
        producers -> {[], producers}
      end

    producer_count = length(producers)
    deleter_count = length(deleters)

    # A chain anchored at the context instance may also end with a trailing
    # deleter: the final context simply loses the entity (a requested one is
    # protected long before this point). A chain of chosen producers only
    # supports the produce → delete → … → produce form.
    allowed? =
      deleter_count == producer_count - 1 or
        (head != [] and deleter_count == producer_count)

    if allowed? do
      for ordered_producers <- permutations(permutable),
          ordered_deleters <- permutations(deleters),
          sequence = interleave(head ++ ordered_producers, ordered_deleters),
          sequence_consistent?(state, sequence, edges),
          do: sequence
    else
      []
    end
  end

  defp interleave([], []), do: []

  defp interleave([producer | producers], deleters) do
    case deleters do
      [] -> [producer | producers]
      [deleter | deleters] -> [producer, deleter | interleave(producers, deleters)]
    end
  end

  defp sequence_consistent?(state, sequence, acc) do
    requires = requires_with_extra_edges(state, acc)

    sequence
    |> ordered_pairs()
    |> Enum.all?(fn {before_cmd, after_cmd} ->
      not reaches?(requires, before_cmd, after_cmd)
    end)
  end

  defp requires_with_extra_edges(state, extra_edges) do
    Enum.reduce(extra_edges, state.requires, fn {before_cmd, after_cmd}, requires ->
      Map.update(requires, after_cmd, MapSet.new([before_cmd]), &MapSet.put(&1, before_cmd))
    end)
  end

  defp ordered_pairs(sequence) do
    for {before_cmd, i} <- Enum.with_index(sequence),
        {after_cmd, j} <- Enum.with_index(sequence),
        i < j,
        do: {before_cmd, after_cmd}
  end

  # The virtual context instance is not a command, so it carries no edge.
  defp consecutive_edges(sequence, acc, state) do
    requires = requires_with_extra_edges(state, acc)

    sequence
    |> Enum.zip(tl(sequence))
    |> Enum.reject(fn {before_cmd, after_cmd} ->
      before_cmd == @context_instance or reaches?(requires, after_cmd, before_cmd)
    end)
  end

  defp permutations([]), do: [[]]

  defp permutations(list) do
    for head <- list, tail <- permutations(list -- [head]), do: [head | tail]
  end

  # Materialization into the final-graph invariant consumed by execution.

  defp to_command_graph(solution) do
    nodes =
      Map.new(solution.chosen, fn cmd ->
        {cmd, Node.new(%{name: cmd, required_by: %{}})}
      end)

    graph = %CommandGraph{nodes: nodes}

    graph =
      solution.edges
      |> Enum.reverse()
      |> Enum.reduce(graph, fn {demander, cmd, traits}, graph ->
        CommandGraph.link_nodes(graph, cmd, demander, traits)
      end)

    Enum.reduce(solution.extra_edges, graph, fn {before_cmd, after_cmd}, graph ->
      CommandGraph.link_nodes(graph, before_cmd, after_cmd, [])
    end)
  end
end
