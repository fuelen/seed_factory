defmodule SeedFactory.StressArgsPatternDumpTest do
  use ExUnit.Case, async: false
  @moduletag :stress

  # The args_pattern dimension. Updaters carry value and
  # generate params; their trait declarations fire only when the runtime args
  # match an args_pattern (or an args_match function fed by generate_args).
  # Several declarations of one command carry different patterns, a name is
  # declared on a producer and on an updater, updaters may also produce a side
  # entity so the plan can pick them for reasons other than a trait. Requests
  # ask for traits, sometimes after a producer was already executed on the
  # context. A requested trait missing afterwards is a silent failure; the
  # differential against the previous release shows plans refused for
  # declarations that would never have fired.
  #
  # Usage:
  #   mix test --only stress test/stress/stress_args_pattern_dump_test.exs
  #   STRESS_OUT=<dump.bin> mix test --only stress test/stress/stress_args_pattern_dump_test.exs

  @n_cases (System.get_env("STRESS_N") || "400") |> String.to_integer()

  @values [:a, :b, :c]

  defp gen_schema(seed) do
    :rand.seed(:exsss, {seed * 53 + 7, seed * 59 + 3, seed * 61 + 17})

    n_entities = Enum.random(2..3)
    entities = Enum.map(1..n_entities, &:"e#{&1}")

    n_producers = Enum.random(2..3)

    produced_by_command =
      Enum.map(1..n_producers, fn _ ->
        k = Enum.random(1..min(2, n_entities))
        entities |> Enum.shuffle() |> Enum.take(k) |> Enum.sort()
      end)

    produced_by_command =
      entities
      |> Enum.with_index()
      |> Enum.reduce(produced_by_command, fn {entity, index}, acc ->
        if Enum.any?(acc, &(entity in &1)) do
          acc
        else
          List.update_at(acc, rem(index, length(acc)), &Enum.uniq([entity | &1]))
        end
      end)

    n_updaters = Enum.random(1..3)

    updaters =
      Enum.map(1..n_updaters, fn index ->
        value_params =
          Enum.map(1..Enum.random(1..2), fn position ->
            {:"p#{position}", Enum.random(@values)}
          end)

        generate_param =
          if :rand.uniform() < 0.25 do
            [{:g, Enum.random(@values)}]
          else
            []
          end

        side_entity =
          if :rand.uniform() < 0.4 do
            :"s#{index}"
          end

        %{
          name: :"u#{index}",
          entity: Enum.random(entities),
          value_params: value_params,
          generate_param: generate_param,
          side_entity: side_entity
        }
      end)

    n_traits = Enum.random(2..5)

    {traits, _by_entity} =
      Enum.reduce(1..n_traits, {[], %{}}, fn index, {acc, by_entity} ->
        entity = Enum.random(entities)
        name = :"t#{index}"

        updaters_of_entity = Enum.filter(updaters, &(&1.entity == entity))

        producers_of_entity =
          produced_by_command
          |> Enum.with_index(1)
          |> Enum.filter(fn {p, _idx} -> entity in p end)
          |> Enum.map(fn {_p, idx} -> :"c#{idx}" end)

        prior = Map.get(by_entity, entity, [])

        from =
          if prior != [] and updaters_of_entity != [] and :rand.uniform() < 0.6 do
            Enum.random(prior)
          end

        declarations =
          cond do
            from != nil ->
              [updater_declaration(name, entity, from, Enum.random(updaters_of_entity))]

            updaters_of_entity != [] and :rand.uniform() < 0.4 ->
              [updater_declaration(name, entity, nil, Enum.random(updaters_of_entity))]

            producers_of_entity != [] ->
              [
                %{
                  name: name,
                  entity: entity,
                  from: nil,
                  exec: Enum.random(producers_of_entity),
                  args: nil
                }
              ]

            true ->
              []
          end

        # The DSL refuses one name declared twice on one command, so the
        # duplicate goes to another updater of the entity.
        duplicates =
          with [decl] <- declarations,
               true <- :rand.uniform() < 0.5,
               [_ | _] = others <- Enum.reject(updaters_of_entity, &(&1.name == decl.exec)) do
            [updater_declaration(name, entity, from, Enum.random(others))]
          else
            _ -> []
          end

        case declarations ++ duplicates do
          [] -> {acc, by_entity}
          decls -> {acc ++ decls, Map.update(by_entity, entity, [name], &(&1 ++ [name]))}
        end
      end)

    # A transition's updater may re-declare the very trait it transitions
    # from, conditionally: the re-add fires or not depending on the args.
    re_adds =
      for transition <- traits,
          transition.from != nil,
          :rand.uniform() < 0.5,
          updater = Enum.find(updaters, &(&1.name == transition.exec)),
          not Enum.any?(traits, &(&1.name == transition.from and &1.exec == updater.name)),
          do: updater_declaration(transition.from, transition.entity, nil, updater)

    traits = traits ++ Enum.uniq_by(re_adds, &{&1.name, &1.exec})

    # A third of the programs target the review-8 finding 1.2 shape: the
    # entity already carries the requested trait, the plan picks an updater
    # for the trait of its side entity, and that updater transitions away from
    # the requested trait while re-declaring it under a condition.
    {traits, targeted} = target_re_add(traits, updaters, n_producers)

    trait_names_by_entity =
      traits
      |> Enum.group_by(& &1.entity, & &1.name)
      |> Map.new(fn {entity, names} -> {entity, Enum.uniq(names)} end)

    # Every side entity gets a creation trait of its own. Requesting the side
    # entity together with that trait makes the updater a plain choice for a
    # trait; requesting it bare puts the requested traits' declarations of the
    # updater on the edge (trait preference), which fixes their args.
    side_traits =
      for updater <- updaters, updater.side_entity != nil do
        %{
          name: :"t#{updater.side_entity}",
          entity: updater.side_entity,
          from: nil,
          exec: updater.name,
          args: nil
        }
      end

    traits = traits ++ side_traits
    side_entities = updaters |> Enum.map(& &1.side_entity) |> Enum.reject(&is_nil/1)

    request_entities =
      entities |> Enum.shuffle() |> Enum.take(Enum.random(1..n_entities)) |> Enum.sort()

    request_sides =
      for side <- side_entities, :rand.uniform() < 0.4 do
        if :rand.uniform() < 0.5 do
          {side, [:"t#{side}"]}
        else
          side
        end
      end

    request =
      Enum.map(request_entities, fn entity ->
        names = Map.get(trait_names_by_entity, entity, [])

        if names != [] and :rand.uniform() < 0.7 do
          {entity, names |> Enum.shuffle() |> Enum.take(Enum.random(1..2)) |> Enum.sort()}
        else
          entity
        end
      end) ++ request_sides

    # Half of the programs start with a producer already executed, preferably
    # one that applies a requested trait, so the request finds it in place.
    requested_names =
      Enum.flat_map(request, fn
        {_entity, names} -> names
        _entity -> []
      end)

    creators =
      for trait <- traits,
          trait.from == nil,
          trait.name in requested_names,
          uniq: true,
          do: trait.exec

    pre_exec =
      cond do
        :rand.uniform() >= 0.5 -> nil
        creators != [] and :rand.uniform() < 0.7 -> Enum.random(creators)
        true -> :"c#{Enum.random(1..n_producers)}"
      end

    {request, pre_exec} =
      case targeted do
        nil -> {request, pre_exec}
        %{request: request, pre_exec: pre_exec} -> {request, pre_exec}
      end

    %{
      producers: produced_by_command,
      updaters: updaters,
      traits: traits,
      request: request,
      steps: Enum.reject([pre_exec && {:exec, pre_exec}, {:produce, request}], &(&1 == nil))
    }
  end

  defp target_re_add(traits, updaters, n_producers) do
    producers = Enum.map(1..n_producers, &:"c#{&1}")

    transitions =
      for trait <- traits,
          trait.from != nil,
          updater = Enum.find(updaters, &(&1.name == trait.exec)),
          updater.side_entity != nil,
          Enum.any?(traits, &(&1.name == trait.from and &1.from == nil and &1.exec in producers)),
          do: {trait, updater}

    if transitions != [] and :rand.uniform() < 0.35 do
      {transition, updater} = Enum.random(transitions)

      creator =
        traits
        |> Enum.filter(&(&1.name == transition.from and &1.from == nil and &1.exec in producers))
        |> Enum.random()

      re_add = updater_declaration(transition.from, transition.entity, nil, updater, :conditional)

      traits =
        case Enum.split_with(traits, &(&1.name == re_add.name and &1.exec == re_add.exec)) do
          {[], rest} -> rest ++ [re_add]
          {[_existing], rest} -> rest ++ [re_add]
        end

      request = [
        {transition.entity, [transition.from]},
        {updater.side_entity, [:"t#{updater.side_entity}"]}
      ]

      {traits, %{request: request, pre_exec: creator.exec}}
    else
      {traits, nil}
    end
  end

  # A declaration on an updater fires under an args_pattern over the
  # updater's params, under an args_match/generate_args pair, or always.
  defp updater_declaration(name, entity, from, updater, mode \\ :any) do
    params = updater.value_params ++ updater.generate_param

    roll =
      case mode do
        :any -> :rand.uniform()
        :conditional -> :rand.uniform() * 0.7
      end

    args =
      case roll do
        r when r < 0.55 ->
          keys =
            params |> Enum.map(&elem(&1, 0)) |> Enum.shuffle() |> Enum.take(Enum.random(1..2))

          {:pattern, Map.new(keys, fn key -> {key, pick_pattern_value(params, key)} end)}

        r when r < 0.7 ->
          {key, _default} = Enum.random(params)
          {:match, key, Enum.random(@values)}

        _ ->
          nil
      end

    %{name: name, entity: entity, from: from, exec: updater.name, args: args}
  end

  # Half of the patterns repeat the default so they fire at runtime; the other
  # half contradict it.
  defp pick_pattern_value(params, key) do
    default = Keyword.fetch!(params, key)

    if :rand.uniform() < 0.5 do
      default
    else
      Enum.random(@values -- [default])
    end
  end

  defp build_module(seed, schema) do
    mod = :"Elixir.StressArgsPatternSchema#{seed}"

    producers_code =
      schema.producers
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {produced, index} ->
        result_map =
          Enum.map_join(produced, ", ", fn entity ->
            "#{entity}: {:c#{index}, #{inspect(entity)}}"
          end)

        produces =
          Enum.map_join(produced, "\n", fn entity -> "    produce #{inspect(entity)}" end)

        """
          command :c#{index} do
            resolve(fn _ -> {:ok, %{#{result_map}}} end)
        #{produces}
          end
        """
      end)

    updaters_code =
      Enum.map_join(schema.updaters, "\n", fn updater ->
        value_params =
          Enum.map_join(updater.value_params, "\n", fn {key, default} ->
            "    param #{inspect(key)}, value: #{inspect(default)}"
          end)

        generate_param =
          Enum.map_join(updater.generate_param, "\n", fn {key, value} ->
            "    param #{inspect(key)}, generate: fn -> #{inspect(value)} end"
          end)

        {side_result, side_produce} =
          case updater.side_entity do
            nil ->
              {"", ""}

            side ->
              {", #{side}: {#{inspect(updater.name)}, #{inspect(side)}}",
               "    produce #{inspect(side)}"}
          end

        """
          command #{inspect(updater.name)} do
            param #{inspect(updater.entity)}, entity: #{inspect(updater.entity)}
        #{value_params}
        #{generate_param}
            resolve(fn _ -> {:ok, %{#{updater.entity}: {#{inspect(updater.name)}, #{inspect(updater.entity)}}#{side_result}}} end)
            update #{inspect(updater.entity)}
        #{side_produce}
          end
        """
      end)

    traits_code =
      Enum.map_join(schema.traits, "\n", fn trait ->
        from =
          if trait.from do
            "    from #{inspect(trait.from)}\n"
          else
            ""
          end

        exec_opts =
          case trait.args do
            nil ->
              ""

            {:pattern, pattern} ->
              ", args_pattern: #{inspect(pattern)}"

            {:match, key, value} ->
              ", args_match: fn args -> args[#{inspect(key)}] == #{inspect(value)} end, " <>
                "generate_args: fn -> %{#{key}: #{inspect(value)}} end"
          end

        """
          trait #{inspect(trait.name)}, #{inspect(trait.entity)} do
        #{from}    exec #{inspect(trait.exec)}#{exec_opts}
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
          for name <- trait_names, name not in current, do: {entity, name}
        else
          [entity]
        end
    end)
  end

  defp run_program(context, schema) do
    Enum.reduce(schema.steps, context, fn
      {:exec, cmd}, ctx -> SeedFactory.exec(ctx, cmd)
      {:produce, request}, ctx -> SeedFactory.produce(ctx, request)
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

            task =
              Task.async(fn ->
                try do
                  {:ok, run_program(context, schema)}
                rescue
                  e -> {:error, e}
                end
              end)

            result =
              case Task.yield(task, 4_000) || Task.shutdown(task, :brutal_kill) do
                {:ok, r} -> r
                nil -> :timeout
              end

            outcome =
              case result do
                :timeout ->
                  :hang

                {:ok, ctx} ->
                  case missing_in_context(ctx, schema.request) do
                    [] -> :ok
                    missing -> {:silent_missing, missing}
                  end

                {:error, e} ->
                  {:raised, e.__struct__}
              end

            [{seed, Map.merge(schema, %{outcome: outcome, satisfiable: nil, source: source})}]
        end
      end)

    if out_path do
      File.write!(out_path, :erlang.term_to_binary(Map.new(results)))
    end

    assert SeedFactory.StressOutcomes.alarming(results) == []
  end
end
