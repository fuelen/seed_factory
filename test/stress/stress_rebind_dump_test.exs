defmodule SeedFactory.StressRebindDumpTest do
  use ExUnit.Case, async: false
  @moduletag :stress

  # Rebinding flows. Sequences of produce with {entity,
  # alias} rebinding, produce with traits + as:, rebind/3 blocks wrapping
  # produce or exec, and pre_produce with rebinding. Checks that an :ok step
  # leaves the aliased entities (with requested traits) under the alias.
  # Purely differential oracle: run with STRESS_OUT in both checkouts.

  @n_cases (System.get_env("STRESS_N") || "150") |> String.to_integer()

  defp gen_schema(seed) do
    :rand.seed(:exsss, {seed * 53 + 17, seed * 59 + 19, seed * 61 + 23})

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

    n_traits = Enum.random(0..4)

    {traits, _by_entity} =
      Enum.reduce(1..n_traits//1, {[], %{}}, fn i, {acc, by_entity} ->
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
            {acc ++ [trait], Map.update(by_entity, entity, [name], &[name | &1])}
        end
      end)

    trait_names_by_entity =
      traits
      |> Enum.group_by(& &1.entity, & &1.name)
      |> Map.new(fn {e, ns} -> {e, Enum.uniq(ns)} end)

    all_commands =
      Enum.map(1..n_producers, &:"c#{&1}") ++ Enum.map(1..n_updaters//1, &:"u#{&1}")

    siblings_of = fn e ->
      # entities co-produced with e by any command producing e
      produced_by_command
      |> Enum.filter(&(e in &1))
      |> List.flatten()
      |> Enum.uniq()
    end

    n_steps = Enum.random(3..4)

    steps =
      Enum.map(1..n_steps, fn step_i ->
        alias_for = fn e -> :"#{e}_r#{step_i}" end

        case :rand.uniform() do
          r when r < 0.35 ->
            # produce with rebinding rules; sometimes rebind all siblings
            # (clean second instance), sometimes only the entity (EAE trap)
            e = Enum.random(entities)

            rebound =
              if :rand.uniform() < 0.6 do
                Enum.map(siblings_of.(e), &{&1, alias_for.(&1)})
              else
                [{e, alias_for.(e)}]
              end

            {:produce_rebound, Enum.uniq(rebound)}

          r when r < 0.55 ->
            # produce with traits + as:
            e = Enum.random(entities)
            names = Map.get(trait_names_by_entity, e, [])

            trait_names =
              if names != [] and :rand.uniform() < 0.7 do
                names |> Enum.shuffle() |> Enum.take(Enum.random(1..2)) |> Enum.sort()
              else
                []
              end

            {:produce_as, e, trait_names, alias_for.(e)}

          r when r < 0.70 ->
            # plain produce (no rebinding) to mix instances
            k = Enum.random(1..n_entities)
            step_entities = entities |> Enum.shuffle() |> Enum.take(k) |> Enum.sort()
            {:produce, Enum.map(step_entities, &{&1, []})}

          r when r < 0.85 ->
            # rebind/3 wrapping produce
            e = Enum.random(entities)
            rebinding = Enum.map(siblings_of.(e), &{&1, alias_for.(&1)})
            {:rebind_produce, Enum.uniq(rebinding), [{e, []}]}

          _ ->
            # rebind/3 wrapping exec
            cmd = Enum.random(all_commands)

            produced =
              case Atom.to_string(cmd) do
                "c" <> i ->
                  idx = String.to_integer(i)
                  Enum.at(produced_by_command, idx - 1)

                "u" <> i ->
                  [Enum.at(updated_by_command, String.to_integer(i) - 1)]
              end

            rebinding = Enum.map(produced, &{&1, alias_for.(&1)})
            {:rebind_exec, Enum.uniq(rebinding), cmd}
        end
      end)

    %{
      producers: produced_by_command,
      deps: deps_by_command,
      updaters: updated_by_command,
      traits: traits,
      steps: steps
    }
  end

  defp build_module(seed, schema) do
    mod = :"Elixir.StressRebindSchema#{seed}"

    producers_code =
      Enum.zip(schema.producers, schema.deps)
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {{produced, deps}, i} ->
        result_map = Enum.map_join(produced, ", ", fn e -> "#{e}: {:c#{i}, #{inspect(e)}}" end)
        produces = Enum.map_join(produced, "\n", fn e -> "    produce #{inspect(e)}" end)

        params =
          Enum.map_join(deps, "\n", fn e -> "    param #{inspect(e)}, entity: #{inspect(e)}" end)

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
            param #{inspect(entity)}, entity: #{inspect(entity)}
            resolve(fn _ -> {:ok, %{#{entity}: {:u#{i}, #{inspect(entity)}}}} end)
            update #{inspect(entity)}
          end
        """
      end)

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
    #{traits_code}
    end
    """

    Code.compile_string(code)
    {:ok, mod, code}
  rescue
    _e in Spark.Error.DslError -> :skip
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

  defp check_bindings(ctx, expectations) do
    Enum.flat_map(expectations, fn {binding, trait_names} ->
      if Map.has_key?(ctx, binding) do
        current = ctx.__seed_factory_meta__.current_traits[binding] || []
        for t <- trait_names, t not in current, do: {binding, t}
      else
        [binding]
      end
    end)
  end

  defp run_step(ctx, step) do
    {fun, expectations} =
      case step do
        {:produce_rebound, rebinding} ->
          {fn -> SeedFactory.produce(ctx, rebinding) end,
           Enum.map(rebinding, fn {_e, a} -> {a, []} end)}

        {:produce_as, e, trait_names, alias_name} ->
          {fn -> SeedFactory.produce(ctx, [{e, trait_names ++ [as: alias_name]}]) end,
           [{alias_name, trait_names}]}

        {:produce, request} ->
          {fn -> SeedFactory.produce(ctx, request) end,
           Enum.map(request, fn {e, ts} -> {e, ts} end)}

        {:rebind_produce, rebinding, request} ->
          {fn ->
             SeedFactory.rebind(ctx, rebinding, fn c -> SeedFactory.produce(c, request) end)
           end,
           Enum.map(request, fn {e, ts} ->
             {Keyword.get(rebinding, e, e), ts}
           end)}

        {:rebind_exec, rebinding, cmd} ->
          {fn -> SeedFactory.rebind(ctx, rebinding, fn c -> SeedFactory.exec(c, cmd) end) end,
           Enum.map(rebinding, fn {_e, a} -> {a, []} end)}
      end

    case run_with_timeout(fun) do
      :timeout ->
        {:halt, :timeout}

      {:error, e} ->
        {:cont, ctx, {:raised, e.__struct__}}

      {:ok, new_ctx} ->
        case check_bindings(new_ctx, expectations) do
          [] -> {:cont, new_ctx, :ok}
          missing -> {:cont, new_ctx, {:silent_missing, missing}}
        end
    end
  end

  defp run_program(ctx, schema) do
    Enum.reduce_while(schema.steps, {ctx, []}, fn step, {ctx, outcomes} ->
      case run_step(ctx, step) do
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
