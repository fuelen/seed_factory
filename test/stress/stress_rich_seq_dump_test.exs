defmodule SeedFactory.StressRichSeqDumpTest do
  use ExUnit.Case, async: false
  @moduletag :stress

  # Combines the dimensions the existing generators keep
  # apart. Producer commands take entity params (deps) with optional
  # with_traits, on top of traits (creation + transitions + duplicate
  # declarations), updaters, and deleters. Deps may reach entities whose
  # non-first producers have a larger index, so runtime dependency cycles the
  # compile check cannot see are generated too. Purely differential oracle.

  @n_cases (System.get_env("STRESS_N") || "400") |> String.to_integer()

  defp gen_schema(seed) do
    :rand.seed(:exsss, {seed * 23 + 1, seed * 29 + 3, seed * 31 + 7})

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

    # Unused, kept for the random stream: dropping the draw would renumber
    # every seed this generator ever produced.
    _request_entities =
      entities |> Enum.shuffle() |> Enum.take(Enum.random(1..n_entities)) |> Enum.sort()

    n_steps = Enum.random(2..3)

    requests =
      Enum.map(1..n_steps, fn _ ->
        step_entities =
          entities |> Enum.shuffle() |> Enum.take(Enum.random(1..n_entities)) |> Enum.sort()

        Enum.map(step_entities, fn e ->
          names = Map.get(trait_names_by_entity, e, [])

          if names != [] and :rand.uniform() < 0.4 do
            {e, names |> Enum.shuffle() |> Enum.take(Enum.random(1..2)) |> Enum.sort()}
          else
            e
          end
        end)
      end)

    request = requests

    %{
      producers: produced_by_command,
      deps: deps_by_command,
      dep_traits: dep_traits_by_command,
      updaters: updated_by_command,
      updater_with_traits: updater_with_traits,
      deleter: deleter,
      deleter_with_traits: deleter_with_traits,
      traits: traits,
      request: request
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
    mod = :"Elixir.StressRichSeqSchema#{seed}"

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
    Enum.flat_map(request, fn
      entity when is_atom(entity) ->
        if Map.has_key?(ctx, entity) do
          []
        else
          [entity]
        end

      {entity, trait_names} ->
        if Map.has_key?(ctx, entity) do
          current = ctx.__seed_factory_meta__.current_traits[entity] || []
          for t <- trait_names, t not in current, do: {entity, t}
        else
          [entity]
        end
    end)
  end

  defp run_step(ctx, request) do
    task =
      Task.async(fn ->
        try do
          {:ok, SeedFactory.produce(ctx, request)}
        rescue
          e -> {:error, e}
        end
      end)

    case Task.yield(task, 4_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, r} -> r
      nil -> :timeout
    end
  end

  defp run_sequence(ctx, requests, victim) do
    Enum.reduce_while(Enum.with_index(requests, 1), {ctx, :ok, nil}, fn {request, step},
                                                                        {ctx, _out, _s} ->
      case run_step(ctx, request) do
        :timeout ->
          {:halt, {ctx, :hang, step}}

        {:error, e} ->
          {:halt, {ctx, {:raised, e.__struct__}, step}}

        {:ok, new_ctx} ->
          case missing_in_context(new_ctx, request) do
            [] ->
              {:cont, {new_ctx, :ok, nil}}

            missing ->
              if Enum.all?(missing, &(&1 == victim)) do
                {:halt, {new_ctx, {:consumed, missing}, step}}
              else
                {:halt, {new_ctx, {:silent_missing, missing}, step}}
              end
          end
      end
    end)
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
            victim = schema.deleter && schema.deleter.victim
            {_ctx, outcome, _step} = run_sequence(context, schema.request, victim)

            [{seed, Map.merge(schema, %{outcome: outcome, satisfiable: nil, source: source})}]
        end
      end)

    if out_path do
      File.write!(out_path, :erlang.term_to_binary(Map.new(results)))
    end

    assert SeedFactory.StressOutcomes.alarming(results) == []
  end
end
