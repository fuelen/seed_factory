defmodule SeedFactory.StressContainerDumpTest do
  use ExUnit.Case, async: false
  @moduletag :stress

  # Schemas whose entity params sit inside container
  # params (up to two nesting levels, several params per container, param key
  # different from the entity name, with_traits inside containers), driven by
  # mixed produce / pre_produce / exec / pre_exec programs whose exec inputs
  # cover params THROUGH the containers (map and keyword forms mixed per
  # level). Purely differential oracle: run with STRESS_OUT in both checkouts.
  #
  #   STRESS_N=400 STRESS_OUT=<path.bin> mix test test/stress/stress_container_dump_test.exs
  #
  # Compare with test/stress/compare_mixed.exs (same dump format).

  @n_cases (System.get_env("STRESS_N") || "150") |> String.to_integer()

  defp gen_schema(seed) do
    :rand.seed(:exsss, {seed * 53 + 7, seed * 59 + 3, seed * 61 + 17})

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

        k = Enum.random(0..min(3, length(allowed)))
        allowed |> Enum.shuffle() |> Enum.take(k) |> Enum.sort()
      end)

    n_updaters = Enum.random(0..2)
    updated_by_command = Enum.map(1..n_updaters//1, fn _ -> Enum.random(entities) end)

    deleter =
      if :rand.uniform() < 0.3 and n_entities >= 2 do
        victim = Enum.random(entities)
        %{victim: victim, product: Enum.random(entities -- [victim])}
      end

    n_traits = Enum.random(0..3)

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

    pick_with_traits = fn entity, prob ->
      names = Map.get(trait_names_by_entity, entity, [])

      if names != [] and :rand.uniform() < prob do
        [Enum.random(names)]
      else
        []
      end
    end

    # Placement of each dep param: a path of container keys (possibly empty).
    # Param key is pK<i>, distinct from the entity name.
    param_layout_of = fn deps ->
      deps
      |> Enum.with_index(1)
      |> Enum.map(fn {entity, i} ->
        path =
          case :rand.uniform() do
            r when r < 0.35 -> []
            r when r < 0.75 -> [Enum.random([:w1, :w2])]
            _ -> [Enum.random([:w1, :w2]), :inner]
          end

        key =
          if :rand.uniform() < 0.5 do
            entity
          else
            :"p#{i}"
          end

        %{entity: entity, key: key, path: path, with_traits: pick_with_traits.(entity, 0.25)}
      end)
    end

    dep_layout_by_command = Enum.map(deps_by_command, param_layout_of)

    updater_layouts =
      updated_by_command
      |> Enum.map(fn entity ->
        [layout] = param_layout_of.([entity])
        %{layout | with_traits: pick_with_traits.(entity, 0.3)}
      end)

    deleter_layout =
      case deleter do
        nil ->
          nil

        %{victim: victim} ->
          [layout] = param_layout_of.([victim])
          %{layout | with_traits: pick_with_traits.(victim, 0.2)}
      end

    all_commands =
      Enum.map(1..n_producers, &:"c#{&1}") ++
        Enum.map(1..n_updaters//1, &:"u#{&1}") ++
        if deleter, do: [:d1], else: []

    gen_request = fn ->
      step_entities =
        entities |> Enum.shuffle() |> Enum.take(Enum.random(1..n_entities)) |> Enum.sort()

      Enum.map(step_entities, fn e ->
        names = Map.get(trait_names_by_entity, e, [])

        if names != [] and :rand.uniform() < 0.4 do
          {e, [Enum.random(names)]}
        else
          {e, []}
        end
      end)
    end

    n_steps = Enum.random(3..4)

    steps =
      Enum.map(1..n_steps, fn _i ->
        case :rand.uniform() do
          r when r < 0.30 ->
            {:produce, gen_request.()}

          r when r < 0.45 ->
            {:pre_produce, gen_request.()}

          r when r < 0.80 ->
            cmd = Enum.random(all_commands)

            covered =
              Enum.filter(
                layout_entities(cmd, dep_layout_by_command, updater_layouts, deleter_layout),
                fn _ -> :rand.uniform() < 0.5 end
              )

            {:exec, cmd, covered, :rand.uniform(1000)}

          _ ->
            cmd = Enum.random(all_commands)

            covered =
              Enum.filter(
                layout_entities(cmd, dep_layout_by_command, updater_layouts, deleter_layout),
                fn _ -> :rand.uniform() < 0.5 end
              )

            {:pre_exec, cmd, covered, :rand.uniform(1000)}
        end
      end)

    %{
      producers: produced_by_command,
      deps: deps_by_command,
      dep_layouts: dep_layout_by_command,
      updaters: updated_by_command,
      updater_layouts: updater_layouts,
      deleter: deleter,
      deleter_layout: deleter_layout,
      traits: traits,
      steps: steps
    }
  end

  defp layout_entities(cmd, dep_layout_by_command, updater_layouts, deleter_layout) do
    layouts_of(cmd, dep_layout_by_command, updater_layouts, deleter_layout)
    |> Enum.map(& &1.entity)
  end

  defp layouts_of(cmd, dep_layout_by_command, updater_layouts, deleter_layout) do
    case Atom.to_string(cmd) do
      "c" <> i -> Enum.at(dep_layout_by_command, String.to_integer(i) - 1)
      "u" <> i -> [Enum.at(updater_layouts, String.to_integer(i) - 1)]
      "d" <> _ -> [deleter_layout]
    end
  end

  # Renders params grouped by container path.
  defp params_code(layouts) do
    {top, contained} = Enum.split_with(layouts, &(&1.path == []))

    top_code = Enum.map_join(top, "\n", &param_line(&1, "    "))

    containers =
      contained
      |> Enum.group_by(&hd(&1.path))
      |> Enum.map_join("\n", fn {wrap, members} ->
        {level1, level2} = Enum.split_with(members, &(length(&1.path) == 1))

        inner_code =
          case level2 do
            [] ->
              ""

            _ ->
              inner_params = Enum.map_join(level2, "\n", &param_line(&1, "        "))

              """
                    param :inner do
              #{inner_params}
                    end
              """
          end

        level1_code = Enum.map_join(level1, "\n", &param_line(&1, "      "))

        """
            param #{inspect(wrap)} do
        #{level1_code}
        #{inner_code}    end
        """
      end)

    top_code <> "\n" <> containers
  end

  defp param_line(layout, indent) do
    wt =
      case layout.with_traits do
        [] -> ""
        names -> ", with_traits: #{inspect(names)}"
      end

    "#{indent}param #{inspect(layout.key)}, entity: #{inspect(layout.entity)}#{wt}"
  end

  defp build_module(seed, schema) do
    mod = :"Elixir.StressContainerSchema#{seed}"

    producers_code =
      Enum.zip(schema.producers, schema.dep_layouts)
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {{produced, layouts}, i} ->
        result_map = Enum.map_join(produced, ", ", fn e -> "#{e}: {:c#{i}, #{inspect(e)}}" end)
        produces = Enum.map_join(produced, "\n", fn e -> "    produce #{inspect(e)}" end)

        """
          command :c#{i} do
        #{params_code(layouts)}
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
        #{params_code([Enum.at(schema.updater_layouts, i - 1)])}
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
          #{params_code([schema.deleter_layout])}
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

  # Builds the nested initial_input covering the given entities of a command,
  # choosing map or keyword form per container from the step's form seed.
  defp build_input(cmd, covered, form_seed, schema) do
    layouts =
      layouts_of(cmd, schema.dep_layouts, schema.updater_layouts, schema.deleter_layout)
      |> Enum.filter(&(&1.entity in covered))

    nested =
      Enum.reduce(layouts, %{}, fn layout, acc ->
        put_path(acc, layout.path, layout.key, {:manual, layout.entity})
      end)

    to_forms(nested, form_seed)
  end

  defp put_path(acc, [], key, value), do: Map.put(acc, key, value)

  defp put_path(acc, [step | rest], key, value) do
    inner = Map.get(acc, step, %{})
    Map.put(acc, step, put_path(inner, rest, key, value))
  end

  # Deterministically converts some nesting levels to keyword lists.
  defp to_forms(map, form_seed) when is_map(map) do
    entries =
      map
      |> Enum.sort()
      |> Enum.map(fn {k, v} ->
        if is_map(v) and not is_struct(v) do
          {k, to_forms(v, div(form_seed, 3))}
        else
          {k, v}
        end
      end)

    if rem(form_seed, 3) == 0 do
      entries
    else
      Map.new(entries)
    end
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

      {:exec, cmd, covered, form_seed} ->
        input = build_input(cmd, covered, form_seed, schema)
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

      {:pre_exec, cmd, covered, form_seed} ->
        input = build_input(cmd, covered, form_seed, schema)

        params =
          layouts_of(cmd, schema.dep_layouts, schema.updater_layouts, schema.deleter_layout)
          |> Enum.map(& &1.entity)

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
