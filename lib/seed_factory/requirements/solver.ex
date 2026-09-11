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
  #     (unit propagation), and so is a trait demand a chosen command can
  #     satisfy, with the other declarations kept as fallbacks;
  #   * an already-chosen command satisfying an entity demand is reused, never
  #     duplicated; for a trait demand its declaration is reused first, and
  #     the other declarations follow as fallbacks, so a plan failing on the
  #     reuse can try another route;
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
  #
  # There is no search budget: a pathological schema can keep the search
  # running long, and nothing cuts it short.

  alias SeedFactory.Params
  alias SeedFactory.Requirements.CandidateGraph
  alias SeedFactory.Requirements.CommandGraph
  alias SeedFactory.Requirements.CommandGraph.Node
  alias SeedFactory.Requirements.Restrictions
  alias SeedFactory.Trait

  # The virtual first producer of an entity already sitting in the context:
  # it joins interleave sequences in the leaf check but is not a command, so
  # it never carries an edge and never reaches an error message.
  @context_instance :__context_instance__

  # Every build returns the plan and the top-level request it serves, as
  # `{entity, trait_names}` pairs, so the execution can check the delivery.
  def build_graph(context, entities_with_trait_names) do
    request = canonical(entities_with_trait_names)
    restrictions = Restrictions.new(context, request)
    candidate_graph = CandidateGraph.new(context, restrictions, request)
    {solve_and_materialize(candidate_graph, :produce), requested(candidate_graph)}
  end

  def build_graph_for_pre_produce(context, entities_with_trait_names) do
    request = canonical(entities_with_trait_names)
    restrictions = Restrictions.new(context, request)
    candidate_graph = CandidateGraph.new(context, restrictions, request)
    {solve_and_materialize(candidate_graph, :pre_produce), requested(candidate_graph)}
  end

  # A request is a set. The search reads it in one order, the entities and
  # the traits of each by name, so the plan does not depend on how the
  # request is written.
  defp canonical(entities_with_trait_names) do
    entities_with_trait_names
    |> Enum.map(fn {entity, trait_names} -> {entity, Enum.sort(trait_names)} end)
    |> Enum.sort_by(fn {entity, _trait_names} -> entity end)
  end

  def build_graph_for_command(context, command, initial_input) do
    restrictions = Restrictions.new(context, [])

    candidate_graph =
      CandidateGraph.new(context, restrictions, [{:command, command, initial_input}])

    {solve_and_materialize(candidate_graph, :produce), requested(candidate_graph)}
  end

  defp requested(candidate_graph) do
    Enum.map(candidate_graph.request, &{&1.entity, &1.trait_names})
  end

  defp solve_and_materialize(candidate_graph, mode) do
    case solve(initial_state(candidate_graph, mode, true)) do
      {:ok, solution} ->
        to_command_graph(solution)

      {:fail, strict_failure} ->
        # A solution found by the relaxed pass carries the cycle the strict
        # pass refused, so the topological sort reports it downstream.
        case solve(initial_state(candidate_graph, mode, false)) do
          {:ok, solution} -> to_command_graph(solution)
          {:fail, _relaxed_failure} -> raise strict_failure.exception
        end
    end
  end

  defp initial_state(candidate_graph, mode, strict_cycles?) do
    pre_produce? = mode == :pre_produce

    state = %{
      candidate_graph: candidate_graph,
      pre_produce?: pre_produce?,
      chosen: MapSet.new(),
      lost: MapSet.new(),
      phantoms: MapSet.new(),
      edges: [],
      requires: %{},
      producers: %{},
      trait_execs: %{},
      extra_edges: [],
      uncertain_shelters: MapSet.new(),
      stack: [],
      strict_cycles?: strict_cycles?,
      # For a command's own dependencies (exec flows) the request is its
      # parameter list: the plan must not consume what the command is about
      # to receive.
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
  # the canonical request order (or the parameter order). Traits therefore
  # commit greedily in that order and a later conflicting trait fails on its
  # own turn.
  defp next_step(state) do
    results = Enum.map(state.stack, fn demand -> {demand, viable_options(state, demand)} end)

    cond do
      satisfied = Enum.find(results, fn {_, result} -> result == :satisfied end) ->
        {:drop, elem(satisfied, 0)}

      zero = Enum.find(results, fn {_, result} -> match?({:zero, _}, result) end) ->
        {_, {:zero, failure}} = zero
        {:fail, failure}

      unit =
          Enum.find(results, fn {_, result} ->
            match?({:options, [_]}, result) or
                match?({:options, [{:decl, _, :reuse} | _]}, result)
          end) ->
        {demand, {:options, options}} = unit
        {:decide, demand, options}

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
          preferred_candidates(state, node)
        else
          node.candidates
        end

      reuse =
        Enum.find(candidates, fn cmd ->
          MapSet.member?(state.chosen, cmd) and cycle_ok?(state, demander, cmd)
        end)

      if reuse do
        {:options, [{:reuse, reuse, edge_traits(state, node, preferred?, reuse)}]}
      else
        viable =
          for cmd <- candidates,
              viability_failure(state, demander, cmd) == nil,
              do: {:choose, cmd, edge_traits(state, node, preferred?, cmd)}

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
        viable =
          for decl <- node.declarations,
              not lost?(state, decl),
              decl.command != demander,
              declaration_failure(state, demander, decl) == nil,
              do: decl

        {reused, fresh} = Enum.split_with(viable, &MapSet.member?(state.chosen, &1.command))

        options =
          Enum.map(reused, &{:decl, &1, :reuse}) ++
            order_declarations(state, Enum.map(fresh, &{:decl, &1, :choose}))

        case options do
          [] ->
            rejections = declaration_rejections(state, node, demander)
            {:zero, trait_failure(entity, name, demander, {:commands_rejected, rejections})}

          options ->
            {:options, options}
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

  # The requested traits' declarations of the command ride the edge of an
  # entity demand without traits of its own, minus the declarations that lost
  # their trait's resolution: the winner applies the trait, not them. A
  # declaration whose pattern contradicts another rider's, or a pattern
  # already fixed on the command, stays off the edge: the trait demands
  # decide between such declarations, with backtracking.
  defp edge_traits(state, node, preferred?, cmd) do
    if preferred? do
      riders = live_declarations(state, node, cmd)

      Enum.filter(riders, fn trait ->
        pattern_conflict(state, cmd, trait) == nil and
          not Enum.any?(riders, &(&1 != trait and riders_conflict?(&1, trait)))
      end)
    else
      []
    end
  end

  defp riders_conflict?(fixed_trait, trait) do
    case trait.exec_step.args_pattern do
      pattern when is_map(pattern) -> fixed_pattern_conflict(fixed_trait, pattern) != nil
      nil -> false
    end
  end

  # A command stays preferred for the entity while one of the declarations
  # that made it preferred is still in the running; otherwise it falls back
  # to its place in the declaration order.
  defp preferred_candidates(state, node) do
    preferred =
      Enum.filter(node.preferred_candidates, &(live_declarations(state, node, &1) != []))

    preferred ++ (node.candidates -- preferred)
  end

  defp live_declarations(state, node, cmd) do
    node.traits_by_command
    |> Map.get(cmd, [])
    |> Enum.reject(&MapSet.member?(state.lost, {&1.entity, &1.name, cmd}))
  end

  defp lost?(state, decl) do
    MapSet.member?(state.lost, {decl.trait.entity, decl.trait.name, decl.command})
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
  defp self_consumed_entity(state, cmd) do
    node = Map.fetch!(state.candidate_graph.commands, cmd)
    param_entities = MapSet.new(node.params, & &1.entity)

    Enum.find(node.produces, &MapSet.member?(param_entities, &1))
  end

  # Why a candidate does not pass the viability filters, nil for a viable
  # one. The filters and the failure report share this function, so they
  # cannot drift apart. A chosen command passes every filter but the cycle
  # one, so the cycle arm is the only one to report it.
  defp viability_failure(state, demander, cmd) do
    cond do
      exception = command_collection_failure(state.candidate_graph, cmd) ->
        {:collection, exception}

      reason = viable_conflict_reason(state, demander, cmd) ->
        reason

      entity = deleted_protected_entity(state, cmd) ->
        {:deletes_requested, entity}

      not cycle_ok?(state, demander, cmd) ->
        {:cycle, demander}

      true ->
        nil
    end
  end

  # The failure report asks only about candidates the filters refused.
  defp rejection_reason(state, demander, cmd) do
    viability_failure(state, demander, cmd) || {:cycle, demander}
  end

  # A declaration is unusable when its command is, or when its args_pattern
  # contradicts a pattern a chosen declaration already fixed on the command:
  # the execution merges the patterns riding a command into one argument map.
  defp declaration_failure(state, demander, decl) do
    pattern_conflict(state, decl) || viability_failure(state, demander, decl.command)
  end

  defp pattern_conflict(state, decl) do
    pattern_conflict(state, decl.command, decl.trait)
  end

  defp pattern_conflict(state, cmd, trait) do
    case trait.exec_step.args_pattern do
      pattern when is_map(pattern) ->
        Enum.find_value(state.edges, fn {_demander, edge_cmd, traits} ->
          if edge_cmd == cmd do
            Enum.find_value(traits, &fixed_pattern_conflict(&1, pattern))
          end
        end)

      nil ->
        nil
    end
  end

  defp fixed_pattern_conflict(fixed_trait, pattern) do
    case fixed_trait.exec_step.args_pattern do
      fixed when is_map(fixed) ->
        case first_disagreement(fixed, pattern, []) do
          nil ->
            nil

          {path, fixed_value, value} ->
            {:args_conflict, path, fixed_value, fixed_trait.name, value}
        end

      nil ->
        nil
    end
  end

  defp first_disagreement(fixed, pattern, path) do
    Enum.find_value(pattern, fn {key, value} ->
      case Map.fetch(fixed, key) do
        :error ->
          nil

        {:ok, ^value} ->
          nil

        {:ok, other}
        when is_map(other) and is_map(value) and not is_struct(other) and not is_struct(value) ->
          first_disagreement(other, value, path ++ [key])

        {:ok, other} ->
          {path ++ [key], other, value}
      end
    end)
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
      {:choose, _cmd, _traits} -> safe_after?(state, apply_option(state, item, option))
      {:decl, _decl, :choose} -> safe_after?(state, apply_option(state, item, option))
      _reuse_or_opt -> true
    end
  end

  # Only the damage of the option counts: the demands it pushes must be
  # viable, and a demand already pending or reachable must not lose its last
  # candidate. A demand dead before the option, the demand of a candidate the
  # context already rules out, is no reason to avoid it.
  defp safe_after?(before, state) do
    pushed = state.stack -- before.stack

    not Enum.any?(state.stack ++ soft_demands(state), fn demand ->
      match?({:zero, _}, viable_options(state, demand)) and
        (demand in pushed or not match?({:zero, _}, viable_options(before, demand)))
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
          not lost?(state, decl),
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
            not lost?(state, decl),
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
        |> Map.update!(:trait_execs, &Map.put(&1, {entity, name}, decl.command))
        |> lose_other_declarations(entity, name, decl)
        |> add_edge(demander, decl.command, [decl.trait])
        |> push_prerequisite(entity, decl)

      {{:any, entity, _options, demander}, {:opt, name}} ->
        push_demands(state, [{:trait, entity, name, demander}])
    end
  end

  # The winner of a trait demand is its only exec: the other declarations of
  # the name lose, so they neither ride an edge nor make their command
  # preferred for an entity, and a later demand for the trait reuses the
  # winner. A loser already riding an edge, planned before the trait was
  # resolved, leaves it. Their commands stay available for everything else.
  # Backtracking brings the declarations back when the winner's subtree fails.
  defp lose_other_declarations(state, entity, name, winner) do
    losers =
      state.candidate_graph.traits
      |> Map.fetch!({entity, name})
      |> Map.fetch!(:declarations)
      |> Enum.reject(&(&1.command == winner.command))
      |> Enum.map(&{entity, name, &1.command})

    lost = MapSet.union(state.lost, MapSet.new(losers))

    edges =
      Enum.map(state.edges, fn {demander, cmd, traits} ->
        {demander, cmd, Enum.reject(traits, &MapSet.member?(lost, {&1.entity, &1.name, cmd}))}
      end)

    %{state | lost: lost, edges: edges}
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
    Enum.map(node.declarations, fn decl ->
      cmd = decl.command

      cond do
        cmd == demander ->
          {cmd, :own_trait_demand}

        cmd in tried_commands ->
          {cmd, :prerequisite_failed}

        lost?(state, decl) ->
          {cmd, {:lost_to, node.name, Map.fetch!(state.trait_execs, {node.entity, node.name})}}

        conflict = pattern_conflict(state, decl) ->
          {cmd, conflict}

        true ->
          {cmd, rejection_reason(state, demander, cmd)}
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

  # A consumer is a chosen command reading an entity through a parameter, or
  # the request reading it at the end of the plan (the consumer nil). What it
  # asks for has to hold when it runs, and the order making it hold is decided
  # here, as edges of the plan: a reader before the deleter of its entity or
  # after a re-producer, a consumer before a command that may cost it a trait,
  # a shelter (a re-applier) between a certain loss and its consumer. Each
  # decision is a depth-first search over its alternatives, the plain one
  # first (the reader before the deleter, the applier of the demand as the
  # shelter), so a later requirement the first choice cannot meet sends the
  # search to the next one. Every alternative adds an edge or records an
  # uncertain shelter for a read not yet deferred to prediction, so the search
  # ends; when every alternative fails, the first one's failure is reported.
  # A phantom never runs, so its parameters ask for nothing.
  defp check_consumers(state) do
    case next_read_decision(state) do
      :settled ->
        {:ok, state}

      {:fail, _} = failure ->
        failure

      {:decide, alternatives} ->
        Enum.reduce_while(alternatives, nil, fn alternative, first_failure ->
          case check_consumers(alternative) do
            {:ok, _} = ok -> {:halt, ok}
            {:fail, _} = failure -> {:cont, first_failure || failure}
          end
        end)
    end
  end

  # The first read still to be ordered: the entity reads first, as they place
  # the readers against the deleters and the re-producers, then the trait
  # reads.
  defp next_read_decision(state) do
    requires = current_requires(state)

    with :settled <- next_entity_read_decision(state, requires) do
      next_trait_read_decision(state, requires)
    end
  end

  # The chosen commands in the order they joined the plan, phantoms excluded.
  defp consumers(state) do
    state.edges
    |> Enum.reverse()
    |> Enum.map(fn {_demander, cmd, _traits} -> cmd end)
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(state.phantoms, &1))
  end

  defp trait_requirements(state) do
    request =
      for %{entity: entity, trait_names: names} <- state.candidate_graph.request,
          name <- names,
          do: {entity, name, nil}

    consumed =
      for cmd <- consumers(state),
          param <- Map.fetch!(state.candidate_graph.commands, cmd).params,
          name <- param.trait_names,
          do: {param.entity, name, cmd}

    request ++ consumed
  end

  defp entity_requirements(state) do
    for cmd <- consumers(state),
        param <- Map.fetch!(state.candidate_graph.commands, cmd).params,
        do: {param.entity, cmd}
  end

  defp current_requires(state) do
    requires_with_extra_edges(state, state.extra_edges)
  end

  defp add_edge_after(state, before_cmd, after_cmd) do
    %{state | extra_edges: state.extra_edges ++ [{before_cmd, after_cmd}]}
  end

  defp ensure_after(state, requires, before_cmd, after_cmd) do
    if reaches?(requires, after_cmd, before_cmd) do
      state
    else
      add_edge_after(state, before_cmd, after_cmd)
    end
  end

  defp next_entity_read_decision(state, requires) do
    pairs =
      for {entity, consumer} <- entity_requirements(state),
          deleter <-
            chosen_deleters(state, Map.get(state.candidate_graph.deleters_by_entity, entity, [])),
          deleter != consumer,
          do: {entity, consumer, deleter}

    Enum.find_value(pairs, :settled, fn {entity, consumer, deleter} ->
      entity_read_decision(state, requires, entity, consumer, deleter)
    end)
  end

  # A reader the dependencies put after a deleter of its entity reads a
  # re-produced instance: a chosen producer of the entity after the deleter,
  # already before the reader or orderable before it. A reader unordered
  # against the deleter reads the current instance before it, or such a
  # re-produced one after it. A deletion depends on no argument, so nothing
  # is left for the prediction before each step.
  defp entity_read_decision(state, requires, entity, consumer, deleter) do
    later_producers =
      for producer <- Map.get(state.producers, entity, []),
          reaches?(requires, producer, deleter),
          do: producer

    after_producer =
      for producer <- later_producers,
          not reaches?(requires, producer, consumer),
          do: add_edge_after(state, producer, consumer)

    after_deleter? = reaches?(requires, consumer, deleter)

    cond do
      reaches?(requires, deleter, consumer) ->
        nil

      after_deleter? and Enum.any?(later_producers, &reaches?(requires, consumer, &1)) ->
        nil

      after_deleter? and after_producer == [] ->
        {:fail, deleted_before_consumer(entity, consumer, deleter)}

      after_deleter? ->
        {:decide, after_producer}

      true ->
        {:decide, [add_edge_after(state, consumer, deleter) | after_producer]}
    end
  end

  defp deleted_before_consumer(entity, consumer, deleter) do
    exception =
      SeedFactory.UnproducibleEntityError.exception(
        entity: entity,
        required_by: consumer,
        commands: [deleter],
        cause: :deleted_before_consumer
      )

    %{kind: :other, exception: exception}
  end

  defp next_trait_read_decision(state, requires) do
    Enum.find_value(trait_requirements(state), :settled, fn {entity, name, consumer} ->
      exec = state.trait_execs[{entity, name}]

      if exec != nil and MapSet.member?(state.phantoms, exec) do
        nil
      else
        Enum.find_value(consumers(state), fn command ->
          trait_read_decision(state, requires, entity, name, exec, consumer, command)
        end)
      end
    end)
  end

  # A command costs a consumer a trait when it runs between the applier and
  # the consumer: it certainly removes the trait (executing a command removes
  # the from lists of the traits it applies, minus the traits it applies
  # itself), or it produces the entity anew without certainly applying it.
  # Such a loss forced before the consumer (always, for the request: every
  # command runs before the end of the plan) needs a shelter. A command
  # unordered against the consumer is tried after it first, then before it:
  # the next read check must shelter a certain loss in that second order.
  # A phantom never executes, and a requested trait applied by a phantom is
  # knowingly not delivered. Losses depending on values the plan does not fix
  # are judged by the prediction before each step (Requirements.TraitDelivery).
  defp trait_read_decision(state, requires, entity, name, exec, consumer, command) do
    cond do
      command == consumer or command == exec ->
        nil

      before_consumer?(requires, consumer, command) ->
        case trait_loss(state, command, entity, name) do
          nil ->
            nil

          reason ->
            shelter_decision(state, requires, entity, name, exec, consumer, command, reason)
        end

      reaches?(requires, command, consumer) ->
        nil

      may_remove?(state, command, entity, name) or
          trait_loss(state, command, entity, name) != nil ->
        {:decide,
         [add_edge_after(state, consumer, command), add_edge_after(state, command, consumer)]}

      true ->
        nil
    end
  end

  # The chosen commands applying the trait that can run after the loser and
  # before the consumer: the applier of the demand first, then the commands
  # applying it for sure, then those that may apply it, which the search
  # cannot judge and the prediction before the consumer's step does. Only a
  # certain shelter already in place settles the read immediately. An
  # uncertain one is a fallback even if already in place; record that choice
  # on this branch so checking the remaining reads does not retry the certain
  # alternatives that just failed. Edges only accumulate within the branch,
  # so the chosen fallback stays between this loss and this consumer.
  defp shelter_decision(state, requires, entity, name, exec, consumer, loser, reason) do
    fitting =
      (List.wrap(exec) ++
         appliers(state, entity, name, :sure) ++ appliers(state, entity, name, :maybe))
      |> Enum.uniq()
      |> Enum.filter(&fits_between?(requires, &1, consumer, loser))

    {certain, uncertain} =
      Enum.split_with(fitting, &(&1 == exec or application(state, &1, entity, name) == :sure))

    read = {entity, name, consumer, loser}

    cond do
      Enum.any?(certain, &in_place?(requires, &1, consumer, loser)) or
          MapSet.member?(state.uncertain_shelters, read) ->
        nil

      fitting == [] ->
        {:fail, trait_failure(entity, name, consumer, reason)}

      true ->
        certain_options =
          Enum.map(certain, &place_shelter(state, requires, &1, consumer, loser))

        fallback = %{state | uncertain_shelters: MapSet.put(state.uncertain_shelters, read)}

        uncertain_options =
          Enum.map(uncertain, &place_shelter(fallback, requires, &1, consumer, loser))

        {:decide, certain_options ++ uncertain_options}
    end
  end

  defp fits_between?(requires, applier, consumer, loser) do
    applier != loser and applier != consumer and
      not reaches?(requires, loser, applier) and
      (consumer == nil or not reaches?(requires, applier, consumer))
  end

  defp in_place?(requires, applier, consumer, loser) do
    reaches?(requires, applier, loser) and
      (consumer == nil or reaches?(requires, consumer, applier))
  end

  defp place_shelter(state, requires, applier, consumer, loser) do
    state = ensure_after(state, requires, loser, applier)

    if consumer == nil do
      state
    else
      ensure_after(state, requires, applier, consumer)
    end
  end

  defp appliers(state, entity, name, status) do
    for command <- consumers(state),
        application(state, command, entity, name) == status,
        do: command
  end

  defp trait_loss(state, command, entity, name) do
    removal = List.keyfind(effective_trait_removals(state, command, entity), name, 0)
    producer? = command in Map.get(state.producers, entity, [])

    cond do
      removal != nil ->
        {^name, via} = removal
        {:removed_by_command, command, via.name, name}

      producer? and application(state, command, entity, name) == :cannot ->
        {:re_produced_without, command, entity, name}

      true ->
        nil
    end
  end

  # Whether a declaration of the command carries the trait in its from list,
  # whatever the arguments.
  defp may_remove?(state, command, entity, name) do
    Enum.any?(declared_traits(state, command, entity), &(name in List.wrap(&1.from)))
  end

  # Whether executing the command applies the trait name to the entity for
  # sure, maybe, or cannot.
  defp application(state, command, entity, name) do
    args = literal_args(state, command)

    statuses =
      for trait <- declared_traits(state, command, entity),
          trait.name == name,
          do: firing(state, command, trait, args)

    cond do
      :sure in statuses -> :sure
      :maybe in statuses -> :maybe
      true -> :cannot
    end
  end

  # The trait names executing the command certainly strips from the entity,
  # each paired with the declaration whose from list carries it: a declaration
  # that fires for sure removes its from list, and no declaration that could
  # fire re-adds the name. Anything less certain is not refused here.
  defp effective_trait_removals(state, command, entity) do
    args = literal_args(state, command)

    classified =
      for trait <- declared_traits(state, command, entity),
          do: {trait, firing(state, command, trait, args)}

    re_added = for {trait, status} <- classified, status != :cannot, do: trait.name

    for {trait, :sure} <- classified,
        removed <- List.wrap(trait.from),
        removed not in re_added,
        do: {removed, trait}
  end

  defp declared_traits(state, command, entity) do
    state.candidate_graph.context
    |> SeedFactory.Context.get_traits(entity)
    |> Kernel.||(%{})
    |> Map.get(:by_command_name, %{})
    |> Map.get(command, [])
  end

  # Whether the declaration fires when the command executes, judged against
  # the arguments the plan fixes for the command. An args_match function is
  # opaque here: it fires for sure only as a chosen declaration, whose
  # generated args the execution merges in.
  defp firing(state, command, trait, args) do
    case trait.exec_step do
      %{args_pattern: pattern} when is_map(pattern) ->
        Trait.pattern_firing(pattern, args)

      %{args_match: nil} ->
        :sure

      _ ->
        if chosen_declaration?(state, command, trait) do
          :sure
        else
          :maybe
        end
    end
  end

  defp chosen_declaration?(state, command, trait) do
    Enum.any?(state.edges, fn {_demander, cmd, traits} -> cmd == command and trait in traits end)
  end

  # The arguments the command executes with, as far as the search knows them:
  # the args_patterns of the trait declarations chosen on it over the literal
  # defaults of its params. Generated values are unknown; a chosen args_match
  # declaration merges generated args of unknown shape, so it makes every
  # default unknown as well. Entities are always unknown here.
  defp literal_args(state, command) do
    chosen_traits =
      for {_demander, cmd, traits} <- state.edges, cmd == command, trait <- traits, do: trait

    input =
      chosen_traits
      |> Enum.flat_map(&List.wrap(&1.exec_step.args_pattern))
      |> Enum.reduce(%{}, &deep_merge(&2, &1))

    generated? = Enum.any?(chosen_traits, &(&1.exec_step.generate_args != nil))
    params = SeedFactory.Context.fetch_command!(state.candidate_graph.context, command).params

    Params.known_args(params, input, fn _entity -> :unknown end, not generated?)
  end

  defp deep_merge(left, right) do
    Map.merge(left, right, fn _key, old, new ->
      if is_map(old) and is_map(new) and not is_struct(old) and not is_struct(new) do
        deep_merge(old, new)
      else
        new
      end
    end)
  end

  defp before_consumer?(_requires, nil, _command), do: true

  defp before_consumer?(requires, consumer, command) do
    reaches?(requires, consumer, command)
  end

  # The leaf: several chosen commands producing one entity are legal only when
  # every chosen deleter of that entity fits between two of its producers, in
  # an order compatible with the dependencies. An entity already sitting in
  # the context joins as a virtual first producer pinned to the head of the
  # sequence. The sequence chosen for one entity constrains the others, so the
  # entities are ordered by a joint backtracking search. The ordering edges
  # become part of the plan, and with them in place the state every consumer
  # reads is checked.
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

    order_multi_producers(state, multi ++ producerless, state.extra_edges)
  end

  defp order_multi_producers(state, [], edges) do
    check_consumers(%{state | extra_edges: edges})
  end

  defp order_multi_producers(state, [{entity, producers} | rest], edges) do
    deleters =
      chosen_deleters(state, Map.get(state.candidate_graph.deleters_by_entity, entity, []))

    unorderable = {:fail, unorderable_failure(entity, producers, deleters)}

    Enum.reduce_while(consistent_sequences(state, producers, deleters, edges), unorderable, fn
      sequence, _failure ->
        case order_multi_producers(
               state,
               rest,
               edges ++ consecutive_edges(sequence, edges, state)
             ) do
          {:ok, _} = ok -> {:halt, ok}
          {:fail, _} = failure -> {:cont, failure}
        end
    end)
  end

  defp unorderable_failure(entity, [@context_instance], deleters) do
    exception =
      SeedFactory.UnproducibleEntityError.exception(
        entity: entity,
        required_by: nil,
        commands: deleters,
        cause: :over_deleted
      )

    %{kind: :other, exception: exception}
  end

  defp unorderable_failure(entity, producers, _deleters) do
    exception =
      SeedFactory.UnproducibleEntityError.exception(
        entity: entity,
        required_by: nil,
        commands: producers -- [@context_instance],
        cause: :unorderable
      )

    %{kind: :other, exception: exception}
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

  # The interleave orders of the producers and deleters of one entity that
  # the dependencies allow, built position by position: a command joins a
  # prefix only when no command already placed requires it, so a prefix the
  # dependencies rule out is dropped at once instead of being completed and
  # refused. The orders come as a stream: the joint search over the entities
  # pulls the next one only when the previous one failed downstream.
  defp consistent_sequences(state, producers, deleters, edges) do
    {head, permutable, next} =
      case producers do
        [@context_instance | rest] -> {[@context_instance], rest, :deleter}
        producers -> {[], producers, :producer}
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
      extend(head, permutable, deleters, next, requires_with_extra_edges(state, edges))
    else
      []
    end
  end

  defp extend(placed, [], [], _next, _requires), do: [Enum.reverse(placed)]

  defp extend(placed, producers, deleters, :producer, requires) do
    producers
    |> Stream.filter(&fits_after?(placed, &1, requires))
    |> Stream.flat_map(fn producer ->
      extend([producer | placed], List.delete(producers, producer), deleters, :deleter, requires)
    end)
  end

  defp extend(placed, producers, deleters, :deleter, requires) do
    deleters
    |> Stream.filter(&fits_after?(placed, &1, requires))
    |> Stream.flat_map(fn deleter ->
      extend([deleter | placed], producers, List.delete(deleters, deleter), :producer, requires)
    end)
  end

  defp fits_after?(placed, command, requires) do
    Enum.all?(placed, fn before_cmd -> not reaches?(requires, before_cmd, command) end)
  end

  defp requires_with_extra_edges(state, extra_edges) do
    Enum.reduce(extra_edges, state.requires, fn {before_cmd, after_cmd}, requires ->
      Map.update(requires, after_cmd, MapSet.new([before_cmd]), &MapSet.put(&1, before_cmd))
    end)
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
