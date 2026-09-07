defmodule SeedFactory.StressMixedDumpTest do
  use ExUnit.Case, async: false
  @moduletag :stress

  # Mixed produce / pre_produce / exec / pre_exec programs
  # on one context. Schemas follow the rich-seq shape (producers with deps and
  # with_traits, updaters, deleter, traits with from-transitions and duplicate
  # declarations). Each step also checks flow-specific invariants:
  #   * produce: requested entities and traits present afterwards;
  #   * pre_produce: a requested entity absent before must stay absent;
  #   * exec with covered params: a covered absent entity must stay absent
  #     (unless the command itself produces it);
  #   * pre_exec: every uncovered entity param sits in the context afterwards.
  # Purely differential oracle: run with STRESS_OUT in both checkouts.

  @n_cases (System.get_env("STRESS_N") || "150") |> String.to_integer()

  defp gen_schema(seed) do
    :rand.seed(:exsss, {seed * 37 + 5, seed * 41 + 11, seed * 43 + 13})

    n_entities = Enum.random(3..5)
    entities = Enum.map(1..n_entities, &:"e#{&1}")

    n_producers = Enum.random(3..6)

    produced_by_command =
      Enum.map(1..n_producers, fn _ ->
        k = Enum.random(1..min(3, n_entities))
        entities |> Enum.shuffle() |> Enum.take(k) |> Enum.sort()
      end)

    produced_by_command =
      entities
      |> Enum.with_index()
      |> Enum.reduce(produced_by_command, fn {e, i}, acc ->
        if Enum.any?(acc, &(e in &1)) do
          acc
        else
          List.update_at(acc, rem(i, length(acc)), &Enum.uniq([e | &1]))
        end
      end)

    deps_by_command =
      produced_by_command
      |> Enum.with_index()
      |> Enum.map(fn {produced, i} ->
        allowed =
          Enum.filter(entities, fn e ->
            first = Enum.find_index(produced_by_command, &(e in &1))
            first != nil and first < i and e not in produced
          end)

        k = Enum.random(0..min(2, length(allowed)))
        allowed |> Enum.shuffle() |> Enum.take(k) |> Enum.sort()
      end)

    n_updaters = Enum.random(0..2)
    updated_by_command = Enum.map(1..n_updaters//1, fn _ -> Enum.random(entities) end)

    deleter =
      if :rand.uniform() < 0.3 and n_entities >= 2 do
        victim = Enum.random(entities)
        %{victim: victim, product: Enum.random(entities -- [victim])}
      end

    n_traits = Enum.random(1..5)

    {traits, _by_entity} =
      Enum.reduce(1..n_traits, {[], %{}}, fn i, {acc, by_entity} ->
        entity = Enum.random(entities)

        updaters_of_entity =
          updated_by_command
          |> Enum.with_index(1)
          |> Enum.filter(fn {e, _idx} -> e == entity end)
          |> Enum.map(fn {_e, idx} -> :"u#{idx}" end)

        producers_of_entity =
          produced_by_command
          |> Enum.with_index(1)
          |> Enum.filter(fn {p, _idx} -> entity in p end)
          |> Enum.map(fn {_p, idx} -> :"c#{idx}" end)

        prior = Map.get(by_entity, entity, [])

        from =
          if prior != [] and updaters_of_entity != [] and :rand.uniform() < 0.5 do
            Enum.random(prior)
          end

        exec_candidates =
          if from do
            updaters_of_entity
          else
            producers_of_entity ++ updaters_of_entity
          end

        case exec_candidates do
          [] ->
            {acc, by_entity}

          candidates ->
            name = :"t#{i}"
            exec = Enum.random(candidates)
            trait = %{name: name, entity: entity, from: from, exec: exec}

            dup =
              with true <- :rand.uniform() < 0.3,
                   [_ | _] = others <- Enum.reject(candidates, &(&1 == exec)) do
                [%{name: name, entity: entity, from: from, exec: Enum.random(others)}]
              else
                _ -> []
              end

            {acc ++ [trait | dup], Map.update(by_entity, entity, [name], &[name | &1])}
        end
      end)

    trait_names_by_entity =
      traits
      |> Enum.group_by(& &1.entity, & &1.name)
      |> Map.new(fn {e, ns} -> {e, Enum.uniq(ns)} end)

    pick_with_traits = fn entity, prob ->
      names = Map.get(trait_names_by_entity, entity, [])

      if names != [] and :rand.uniform() < prob do
        [Enum.random(names)]
      else
        []
      end
    end

    dep_traits_by_command =
      Enum.map(deps_by_command, fn deps ->
        Map.new(deps, fn e -> {e, pick_with_traits.(e, 0.3)} end)
      end)

    updater_with_traits =
      updated_by_command
      |> Enum.map(fn entity -> pick_with_traits.(entity, 0.3) end)

    deleter_with_traits =
      case deleter do
        nil -> []
        %{victim: victim} -> pick_with_traits.(victim, 0.2)
      end

    all_commands =
      Enum.map(1..n_producers, &:"c#{&1}") ++
        Enum.map(1..n_updaters//1, &:"u#{&1}") ++
        if deleter, do: [:d1], else: []

    entity_params_of = fn cmd ->
      case Atom.to_string(cmd) do
        "c" <> i -> Enum.at(deps_by_command, String.to_integer(i) - 1)
        "u" <> i -> [Enum.at(updated_by_command, String.to_integer(i) - 1)]
        "d" <> _ -> [deleter.victim]
      end
    end

    gen_request = fn ->
      step_entities =
        entities |> Enum.shuffle() |> Enum.take(Enum.random(1..n_entities)) |> Enum.sort()

      Enum.map(step_entities, fn e ->
        names = Map.get(trait_names_by_entity, e, [])

        if names != [] and :rand.uniform() < 0.4 do
          {e, names |> Enum.shuffle() |> Enum.take(Enum.random(1..2)) |> Enum.sort()}
        else
          {e, []}
        end
      end)
    end

    n_steps = Enum.random(3..4)

    {steps, _prev} =
      Enum.map_reduce(1..n_steps, nil, fn _i, prev ->
        step =
          case :rand.uniform() do
            r when r < 0.40 ->
              request =
                if prev != nil and :rand.uniform() < 0.3 do
                  prev
                else
                  gen_request.()
                end

              {:produce, request}

            r when r < 0.60 ->
              {:pre_produce, gen_request.()}

            r when r < 0.82 ->
              cmd = Enum.random(all_commands)
              params = entity_params_of.(cmd)
              covered = Enum.filter(params, fn _ -> :rand.uniform() < 0.5 end)
              {:exec, cmd, covered}

            _ ->
              cmd = Enum.random(all_commands)
              params = entity_params_of.(cmd)
              covered = Enum.filter(params, fn _ -> :rand.uniform() < 0.5 end)
              {:pre_exec, cmd, covered}
          end

        request = if match?({:produce, _}, step), do: elem(step, 1), else: prev
        {step, request}
      end)

    %{
      producers: produced_by_command,
      deps: deps_by_command,
      dep_traits: dep_traits_by_command,
      updaters: updated_by_command,
      updater_with_traits: updater_with_traits,
      deleter: deleter,
      deleter_with_traits: deleter_with_traits,
      traits: traits,
      steps: steps
    }
  end

  defp param_code(entity, with_traits) do
    wt =
      case with_traits do
        [] -> ""
        names -> ", with_traits: #{inspect(names)}"
      end

    "    param #{inspect(entity)}, entity: #{inspect(entity)}#{wt}"
  end

  defp build_module(seed, schema) do
    mod = :"Elixir.StressMixedSchema#{seed}"

    producers_code =
      Enum.zip(schema.producers, Enum.zip(schema.deps, schema.dep_traits))
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {{produced, {deps, dep_traits}}, i} ->
        result_map = Enum.map_join(produced, ", ", fn e -> "#{e}: {:c#{i}, #{inspect(e)}}" end)
        produces = Enum.map_join(produced, "\n", fn e -> "    produce #{inspect(e)}" end)
        params = Enum.map_join(deps, "\n", fn e -> param_code(e, dep_traits[e]) end)

        """
          command :c#{i} do
        #{params}
            resolve(fn _ -> {:ok, %{#{result_map}}} end)
        #{produces}
          end
        """
      end)

    updaters_code =
      schema.updaters
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {entity, i} ->
        """
          command :u#{i} do
        #{param_code(entity, Enum.at(schema.updater_with_traits, i - 1))}
            resolve(fn _ -> {:ok, %{#{entity}: {:u#{i}, #{inspect(entity)}}}} end)
            update #{inspect(entity)}
          end
        """
      end)

    deleter_code =
      case schema.deleter do
        nil ->
          ""

        %{victim: victim, product: product} ->
          """
            command :d1 do
          #{param_code(victim, schema.deleter_with_traits)}
              resolve(fn _ -> {:ok, %{#{product}: {:d1, #{inspect(product)}}}} end)
              produce #{inspect(product)}
              delete #{inspect(victim)}
            end
          """
      end

    traits_code =
      Enum.map_join(schema.traits, "\n", fn trait ->
        from = if trait.from, do: "    from #{inspect(trait.from)}\n", else: ""

        """
          trait #{inspect(trait.name)}, #{inspect(trait.entity)} do
        #{from}    exec #{inspect(trait.exec)}
          end
        """
      end)

    code = """
    defmodule #{inspect(mod)} do
      use SeedFactory.Schema
    #{producers_code}
    #{updaters_code}
    #{deleter_code}
    #{traits_code}
    end
    """

    Code.compile_string(code)
    {:ok, mod, code}
  rescue
    _e in Spark.Error.DslError -> :skip
  end

  defp missing_in_context(ctx, request) do
    Enum.flat_map(request, fn {entity, trait_names} ->
      if Map.has_key?(ctx, entity) do
        current = ctx.__seed_factory_meta__.current_traits[entity] || []
        for t <- trait_names, t not in current, do: {entity, t}
      else
        [entity]
      end
    end)
  end

  defp run_with_timeout(fun) do
    task =
      Task.async(fn ->
        try do
          {:ok, fun.()}
        rescue
          e -> {:error, e}
        end
      end)

    case Task.yield(task, 4_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, r} -> r
      nil -> :timeout
    end
  end

  defp produces_of(schema, cmd) do
    case Atom.to_string(cmd) do
      "c" <> i -> Enum.at(schema.producers, String.to_integer(i) - 1)
      "u" <> _ -> []
      "d" <> _ -> [schema.deleter.product]
    end
  end

  defp entity_params_of_schema(schema, cmd) do
    case Atom.to_string(cmd) do
      "c" <> i -> Enum.at(schema.deps, String.to_integer(i) - 1)
      "u" <> i -> [Enum.at(schema.updaters, String.to_integer(i) - 1)]
      "d" <> _ -> [schema.deleter.victim]
    end
  end

  defp run_step(ctx, step, schema) do
    case step do
      {:produce, request} ->
        case run_with_timeout(fn -> SeedFactory.produce(ctx, request) end) do
          :timeout ->
            {:halt, :timeout}

          {:error, e} ->
            {:cont, ctx, {:raised, e.__struct__}}

          {:ok, new_ctx} ->
            case missing_in_context(new_ctx, request) do
              [] -> {:cont, new_ctx, :ok}
              missing -> {:cont, new_ctx, {:silent_missing, missing}}
            end
        end

      {:pre_produce, request} ->
        absent_before = for {e, _} <- request, not Map.has_key?(ctx, e), do: e

        case run_with_timeout(fn -> SeedFactory.pre_produce(ctx, request) end) do
          :timeout ->
            {:halt, :timeout}

          {:error, e} ->
            {:cont, ctx, {:raised, e.__struct__}}

          {:ok, new_ctx} ->
            leaked = Enum.filter(absent_before, &Map.has_key?(new_ctx, &1))

            if leaked == [] do
              {:cont, new_ctx, :ok}
            else
              {:cont, new_ctx, {:pre_produced_requested, leaked}}
            end
        end

      {:exec, cmd, covered} ->
        input = Map.new(covered, fn e -> {e, {:manual, e}} end)
        produced = produces_of(schema, cmd)

        absent_covered =
          Enum.filter(covered, fn e -> not Map.has_key?(ctx, e) and e not in produced end)

        case run_with_timeout(fn -> SeedFactory.exec(ctx, cmd, input) end) do
          :timeout ->
            {:halt, :timeout}

          {:error, e} ->
            {:cont, ctx, {:raised, e.__struct__}}

          {:ok, new_ctx} ->
            leaked = Enum.filter(absent_covered, &Map.has_key?(new_ctx, &1))

            if leaked == [] do
              {:cont, new_ctx, :ok}
            else
              {:cont, new_ctx, {:planned_covered, leaked}}
            end
        end

      {:pre_exec, cmd, covered} ->
        input = Map.new(covered, fn e -> {e, {:manual, e}} end)
        params = entity_params_of_schema(schema, cmd)

        case run_with_timeout(fn -> SeedFactory.pre_exec(ctx, cmd, input) end) do
          :timeout ->
            {:halt, :timeout}

          {:error, e} ->
            {:cont, ctx, {:raised, e.__struct__}}

          {:ok, new_ctx} ->
            missing =
              Enum.filter(params, fn e ->
                e not in covered and not Map.has_key?(new_ctx, e)
              end)

            if missing == [] do
              {:cont, new_ctx, :ok}
            else
              {:cont, new_ctx, {:pre_exec_missing_dep, missing}}
            end
        end
    end
  end

  defp run_program(ctx, schema) do
    Enum.reduce_while(schema.steps, {ctx, []}, fn step, {ctx, outcomes} ->
      case run_step(ctx, step, schema) do
        {:halt, :timeout} -> {:halt, {ctx, outcomes ++ [:timeout]}}
        {:cont, new_ctx, outcome} -> {:cont, {new_ctx, outcomes ++ [outcome]}}
      end
    end)
  end

  defp final_state(ctx) do
    keys = (Map.keys(ctx) -- [:__seed_factory_meta__]) |> Enum.sort()

    traits =
      ctx.__seed_factory_meta__.current_traits
      |> Enum.map(fn {k, v} -> {k, Enum.sort(v)} end)
      |> Enum.sort()

    {keys, traits}
  end

  test "dump outcomes" do
    out_path = System.get_env("STRESS_OUT")

    results =
      Enum.flat_map(1..@n_cases, fn seed ->
        schema = gen_schema(seed)

        case build_module(seed, schema) do
          :skip ->
            []

          {:ok, mod, source} ->
            context = SeedFactory.Context.init(%{}, mod)
            {ctx, outcomes} = run_program(context, schema)

            [
              {seed,
               Map.merge(schema, %{
                 outcomes: outcomes,
                 final: final_state(ctx),
                 source: source
               })}
            ]
        end
      end)

    if out_path do
      File.write!(out_path, :erlang.term_to_binary(Map.new(results)))
    end

    assert SeedFactory.StressOutcomes.alarming(results) == []
  end
end
