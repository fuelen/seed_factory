defmodule SeedFactory.StressParameterizedDumpTest do
  use ExUnit.Case, async: false
  @moduletag :stress

  # The parameterized trait dimension. Every entity carries a field `v`, and
  # its trait `p<entity>` declares `_` over `v` on some of its producers and
  # updaters, sometimes next to a fixed field `k`. Commands change `v` only
  # when their declaration fires, so a tracked `{p<entity>, value}` must equal
  # the instance's `v` after every step. Updaters may generate `v`, copy it
  # from a `src` entity so the placeholder sits inside an entity param, produce
  # a side entity the plan picks for another reason, carry an ordinary
  # transition, or assign the value as a transition from the creation trait.
  # Consumers require a value through `with_traits` and record the `v` they
  # saw. Programs mix direct `exec` calls with and without a value and
  # `produce` requests for values, ordinary traits and consumers.
  #
  # A seed runs in one of three modes. In the scalar mode `v` is a plain
  # param, and a third of these programs target the value assigned as a
  # transition: they request the value and the creation trait together, first
  # through `pre_produce`, then through `produce`. In the container mode `v`
  # has nested params whose keys differ from command to command, and requests
  # pass maps, keyword lists, values of another shape and scalars. In the
  # re-creation mode a deleter consumes the entity into an intermediate one, a
  # re-creator produces it anew with a side output, copying `v` from the
  # intermediate when the intermediate has it, and a consumer needs both the
  # value and the side output.
  #
  # A tracked value that disagrees with the instance, a requested trait missing
  # afterwards, a consumer that saw another value, or a request `produce`
  # refuses right after `pre_produce` accepted it is a silent failure.
  #
  # Usage:
  #   mix test --only stress test/stress/stress_parameterized_dump_test.exs
  #   STRESS_OUT=<dump.bin> mix test --only stress test/stress/stress_parameterized_dump_test.exs

  @n_cases (System.get_env("STRESS_N") || "400") |> String.to_integer()

  @values [:a, :b, :c]
  @shapes [[:x], [:y], [:x, :y]]

  defp gen_schema(seed) do
    :rand.seed(:exsss, {seed * 67 + 5, seed * 71 + 13, seed * 73 + 29})

    mode =
      case :rand.uniform() do
        roll when roll < 0.4 -> :scalar
        roll when roll < 0.7 -> :container
        _roll -> :recreate
      end

    # A third of the scalar programs target the value assigned as a transition:
    # the only declaration of pe1 sits on an updater with `from :ne1`.
    targeted = mode == :scalar and :rand.uniform() < 0.3

    entities = Enum.map(1..Enum.random(1..2), &:"e#{&1}")

    command_v = fn ->
      case mode do
        :container -> {:container, Enum.map(Enum.random(@shapes), &{&1, Enum.random(@values)})}
        _mode -> {:value, Enum.random(@values)}
      end
    end

    producers =
      Enum.map(entities, fn entity ->
        %{name: :"c#{entity}", entity: entity, v: command_v.(), k: Enum.random(@values)}
      end)

    extra_producers =
      for index <- 1..Enum.random(0..1)//1 do
        entity = Enum.random(entities)
        %{name: :"x#{index}", entity: entity, v: command_v.(), k: Enum.random(@values)}
      end

    producers = producers ++ extra_producers

    updaters =
      Enum.map(1..Enum.random(1..3), fn index ->
        v =
          case {mode, :rand.uniform()} do
            {:scalar, roll} when roll < 0.25 -> {:generate, Enum.random(@values)}
            {_mode, roll} when roll < 0.5 -> :source
            _roll -> command_v.()
          end

        side_entity =
          if :rand.uniform() < 0.4 do
            :"s#{index}"
          end

        %{
          name: :"u#{index}",
          entity: Enum.random(entities),
          v: v,
          k: Enum.random(@values),
          side_entity: side_entity
        }
      end)

    updaters =
      if targeted do
        List.update_at(updaters, 0, &%{&1 | entity: :e1, v: {:value, Enum.random(@values)}})
      else
        updaters
      end

    recreators =
      for entity <- entities, mode == :recreate, :rand.uniform() < 0.8 do
        %{
          name: :"re#{entity}",
          entity: entity,
          deleter: :"d#{entity}",
          intermediate: :"m#{entity}",
          output: :"o#{entity}",
          v: Enum.random([:copy, {:value, Enum.random(@values)}]),
          intermediate_has_v: :rand.uniform() < 0.6,
          k: Enum.random(@values)
        }
      end

    # At most one declaration of p<entity> per command, as the DSL requires.
    value_declarations =
      for command <- producers ++ updaters ++ recreators,
          :rand.uniform() < 0.7 do
        fixed_k =
          if :rand.uniform() < 0.3 do
            Enum.random(@values)
          end

        placeholder =
          case command.v do
            :source -> "src: %{v: _}"
            :copy -> "#{command.intermediate}: %{v: _}"
            _v -> "v: _"
          end

        from =
          if command in updaters and :rand.uniform() < 0.25 do
            :"n#{command.entity}"
          end

        %{
          name: :"p#{command.entity}",
          entity: command.entity,
          exec: command.name,
          k: fixed_k,
          placeholder: placeholder,
          from: from
        }
      end

    value_declarations =
      if targeted do
        [
          %{name: :pe1, entity: :e1, exec: :u1, k: nil, placeholder: "v: _", from: :ne1}
          | Enum.reject(value_declarations, &(&1.entity == :e1))
        ]
      else
        value_declarations
      end

    status_traits =
      Enum.flat_map(entities, fn entity ->
        creator = Enum.find(producers, &(&1.entity == entity))
        transition_updaters = Enum.filter(updaters, &(&1.entity == entity))

        created = [%{name: :"n#{entity}", entity: entity, exec: creator.name, from: nil}]

        if transition_updaters != [] and :rand.uniform() < 0.6 do
          updater = Enum.random(transition_updaters)

          created ++
            [%{name: :"t#{entity}", entity: entity, exec: updater.name, from: :"n#{entity}"}]
        else
          created
        end
      end)

    side_traits =
      for updater <- updaters, updater.side_entity != nil do
        %{
          name: :"t#{updater.side_entity}",
          entity: updater.side_entity,
          exec: updater.name,
          from: nil
        }
      end

    value_for = fn entity ->
      shapes =
        for declaration <- value_declarations,
            declaration.entity == entity,
            %{v: {:container, params}} <-
              Enum.filter(producers ++ updaters, &(&1.name == declaration.exec)),
            do: Keyword.keys(params)

      case {mode, shapes} do
        {:container, [_ | _]} -> Map.new(Enum.random(shapes), &{&1, Enum.random(@values)})
        _mode -> Enum.random(@values)
      end
    end

    source_v =
      case mode do
        :container -> Map.new(Enum.random(@shapes), &{&1, Enum.random(@values)})
        _mode -> Enum.random(@values)
      end

    consumers =
      for entity <- entities, :rand.uniform() < 0.5 do
        %{
          name: :"use_#{entity}",
          entity: entity,
          output: :"r#{entity}",
          v: value_for.(entity),
          also: nil
        }
      end

    recreation_consumers =
      for recreator <- recreators, :rand.uniform() < 0.7 do
        %{
          name: :"use2_#{recreator.entity}",
          entity: recreator.entity,
          output: :"q#{recreator.entity}",
          v: value_for.(recreator.entity),
          also: recreator.output
        }
      end

    consumers = consumers ++ recreation_consumers
    valued_entities = value_declarations |> Enum.map(& &1.entity) |> Enum.uniq()

    # Values that fit no shape, and keyword lists that do, reach the
    # boundary normalization.
    request_value = fn entity ->
      value =
        case {mode, :rand.uniform()} do
          {:container, roll} when roll < 0.1 -> Enum.random(@values)
          {:container, roll} when roll < 0.2 -> Map.new(Enum.random(@shapes), &{&1, :a})
          _roll -> value_for.(entity)
        end

      if is_map(value) and :rand.uniform() < 0.5 do
        Enum.to_list(value)
      else
        value
      end
    end

    requests =
      Enum.map(1..Enum.random(1..2), fn _ ->
        # A requested entity cannot be consumed by a deleter, so re-creation
        # programs mostly ask only for what the re-creation leads to.
        entity_share =
          if mode == :recreate and recreators != [] do
            0.15
          else
            0.7
          end

        entity_entries =
          for entity <- entities, :rand.uniform() < entity_share do
            value_traits =
              if entity in valued_entities and :rand.uniform() < 0.8 do
                [{:"p#{entity}", request_value.(entity)}]
              else
                []
              end

            status_names =
              if :rand.uniform() < 0.3 do
                [Enum.random(for trait <- status_traits, trait.entity == entity, do: trait.name)]
              else
                []
              end

            traits = value_traits ++ status_names

            if traits == [] do
              entity
            else
              {entity, Enum.uniq_by(traits, &trait_name/1)}
            end
          end

        consumer_entries = for consumer <- consumers, :rand.uniform() < 0.5, do: consumer.output

        side_entries =
          for updater <- updaters, updater.side_entity != nil, :rand.uniform() < 0.3 do
            updater.side_entity
          end

        output_entries =
          for recreator <- recreators, :rand.uniform() < 0.4, do: recreator.output

        case entity_entries ++ consumer_entries ++ side_entries ++ output_entries do
          [] -> [hd(entities)]
          request -> request
        end
      end)

    exec_args = fn command ->
      case {command.v, :rand.uniform() < 0.6} do
        {{:container, params}, true} ->
          keys = params |> Keyword.keys() |> Enum.take_random(Enum.random(1..length(params)))
          value = Map.new(keys, &{&1, Enum.random(@values)})

          if :rand.uniform() < 0.5 do
            [v: Enum.to_list(value)]
          else
            [v: value]
          end

        {{kind, _value}, true} when kind in [:value, :generate] ->
          [v: Enum.random(@values)]

        _no_value ->
          []
      end
    end

    # A producer runs only first: afterwards its entity already exists.
    first_exec =
      if :rand.uniform() < 0.4 do
        producer = Enum.random(producers)
        [{:exec, producer.name, exec_args.(producer)}]
      else
        []
      end

    # One exec per updater: a second one would produce its side entity again.
    updater_execs =
      for(
        _ <- 1..Enum.random(0..2)//1,
        updater = Enum.random(updaters),
        do: {:exec, updater.name, exec_args.(updater)}
      )
      |> Enum.uniq_by(&elem(&1, 1))

    steps =
      first_exec ++
        Enum.shuffle(updater_execs ++ Enum.map(tl(requests), &{:produce, &1})) ++
        [{:produce, hd(requests)}]

    value = Enum.random(@values)

    {steps, requests} =
      case {targeted, :rand.uniform() < 0.5} do
        {false, _together?} ->
          {steps, requests}

        {true, true} ->
          request = [e1: [:ne1, pe1: value]]
          {[{:pre_produce, request}, {:produce, request}], [request]}

        {true, false} ->
          request = [e1: [:ne1]]
          {[{:produce, [e1: [pe1: value]]}, {:produce, request}], [request]}
      end

    %{
      mode: mode,
      producers: producers,
      source_v: source_v,
      updaters: updaters,
      recreators: recreators,
      value_declarations: value_declarations,
      status_traits: status_traits,
      side_traits: side_traits,
      consumers: consumers,
      steps: steps,
      request: hd(requests)
    }
  end

  defp trait_name({name, _value}), do: name
  defp trait_name(name), do: name

  defp declaration_of(schema, command_name) do
    Enum.find(schema.value_declarations, &(&1.exec == command_name))
  end

  defp v_param_code({:value, value}), do: "param :v, value: #{inspect(value)}"
  defp v_param_code({:generate, value}), do: "param :v, generate: fn -> #{inspect(value)} end"
  defp v_param_code(:source), do: "param :src, entity: :src"

  defp v_param_code({:container, params}) do
    nested =
      Enum.map_join(params, "\n", fn {key, value} ->
        "param #{inspect(key)}, value: #{inspect(value)}"
      end)

    """
    param :v do
    #{nested}
    end
    """
  end

  defp build_module(seed, schema) do
    mod = :"Elixir.StressParameterizedSchema#{seed}"

    producers_code =
      Enum.map_join(schema.producers, "\n", fn producer ->
        """
          command #{inspect(producer.name)} do
            #{v_param_code(producer.v)}
            param :k, value: #{inspect(producer.k)}
            resolve(fn args -> {:ok, %{#{producer.entity}: %{v: args.v, k: args.k}}} end)
            produce #{inspect(producer.entity)}
          end
        """
      end)

    updaters_code =
      Enum.map_join(schema.updaters, "\n", fn updater ->
        v_read =
          case updater.v do
            :source -> "args.src.v"
            _v -> "args.v"
          end

        # The resolver changes v exactly when the declaration fires.
        assigns =
          case declaration_of(schema, updater.name) do
            nil -> "false"
            %{k: nil} -> "true"
            %{k: fixed} -> "args.k == #{inspect(fixed)}"
          end

        {side_result, side_produce} =
          case updater.side_entity do
            nil -> {"", ""}
            side -> {", #{side}: :side", "produce #{inspect(side)}"}
          end

        entity = updater.entity

        """
          command #{inspect(updater.name)} do
            param #{inspect(entity)}, entity: #{inspect(entity)}
            #{v_param_code(updater.v)}
            param :k, value: #{inspect(updater.k)}

            resolve(fn args ->
              instance =
                if #{assigns} do
                  %{args.#{entity} | v: #{v_read}}
                else
                  args.#{entity}
                end

              {:ok, %{#{entity}: instance#{side_result}}}
            end)

            update #{inspect(entity)}
            #{side_produce}
          end
        """
      end)

    recreators_code =
      Enum.map_join(schema.recreators, "\n", fn recreator ->
        entity = recreator.entity
        intermediate = recreator.intermediate

        intermediate_value =
          if recreator.intermediate_has_v do
            "%{v: args.#{entity}.v}"
          else
            "%{w: :w}"
          end

        {v_param, v_read} =
          case recreator.v do
            :copy -> {"", "args.#{intermediate}[:v]"}
            {:value, value} -> {"param :v, value: #{inspect(value)}", "args.v"}
          end

        """
          command #{inspect(recreator.deleter)} do
            param #{inspect(entity)}, entity: #{inspect(entity)}
            resolve(fn args -> {:ok, %{#{intermediate}: #{intermediate_value}}} end)
            delete #{inspect(entity)}
            produce #{inspect(intermediate)}
          end

          command #{inspect(recreator.name)} do
            param #{inspect(intermediate)}, entity: #{inspect(intermediate)}
            #{v_param}
            param :k, value: #{inspect(recreator.k)}

            resolve(fn args ->
              {:ok, %{#{entity}: %{v: #{v_read}, k: args.k}, #{recreator.output}: :output}}
            end)

            produce #{inspect(entity)}
            produce #{inspect(recreator.output)}
          end
        """
      end)

    consumers_code =
      Enum.map_join(schema.consumers, "\n", fn consumer ->
        also =
          case consumer.also do
            nil -> ""
            output -> "param #{inspect(output)}, entity: #{inspect(output)}"
          end

        """
          command #{inspect(consumer.name)} do
            param #{inspect(consumer.entity)}, entity: #{inspect(consumer.entity)}, with_traits: [p#{consumer.entity}: #{inspect(consumer.v)}]
            #{also}
            resolve(fn args -> {:ok, %{#{consumer.output}: %{v: args.#{consumer.entity}.v}}} end)
            produce #{inspect(consumer.output)}
          end
        """
      end)

    source_code = """
      command :csrc do
        param :v, value: #{inspect(schema.source_v)}
        resolve(fn args -> {:ok, %{src: %{v: args.v}}} end)
        produce :src
      end
    """

    value_traits_code =
      Enum.map_join(schema.value_declarations, "\n", fn declaration ->
        pattern =
          case declaration.k do
            nil -> "%{#{declaration.placeholder}}"
            fixed -> "%{#{declaration.placeholder}, k: #{inspect(fixed)}}"
          end

        from =
          if declaration.from do
            "    from #{inspect(declaration.from)}\n"
          else
            ""
          end

        """
          trait #{inspect(declaration.name)}, #{inspect(declaration.entity)} do
        #{from}    exec #{inspect(declaration.exec)}, args_pattern: #{pattern}
          end
        """
      end)

    status_traits_code =
      Enum.map_join(schema.status_traits ++ schema.side_traits, "\n", fn trait ->
        from =
          if trait.from do
            "    from #{inspect(trait.from)}\n"
          else
            ""
          end

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
    #{source_code}
    #{updaters_code}
    #{recreators_code}
    #{consumers_code}
    #{value_traits_code}
    #{status_traits_code}
    end
    """

    Code.compile_string(code)
    {:ok, mod, code}
  rescue
    _e in Spark.Error.DslError -> :skip
  end

  # A keyword list becomes a map when it holds exactly the keys of a container
  # declaration of the trait. Otherwise a plain declaration takes it as is.
  defp expected_reference(schema, entity, {name, value}) when is_list(value) and value != [] do
    shapes =
      for declaration <- schema.value_declarations,
          declaration.entity == entity,
          %{v: {:container, params}} <-
            Enum.filter(schema.producers ++ schema.updaters, &(&1.name == declaration.exec)),
          do: params |> Keyword.keys() |> Enum.sort()

    if Enum.sort(Keyword.keys(value)) in shapes do
      {name, Map.new(value)}
    else
      {name, value}
    end
  end

  defp expected_reference(_schema, _entity, reference), do: reference

  # A tracked value has to be the value the instance holds.
  defp inconsistent_values(ctx) do
    for {entity, traits} <- ctx.__seed_factory_meta__.current_traits,
        {name, value} <- traits,
        name == :"p#{entity}",
        not (Map.has_key?(ctx, entity) and ctx[entity].v === value),
        do: {:tracked, entity, value}
  end

  defp missing_in_context(ctx, request, schema) do
    Enum.flat_map(request, fn
      {entity, trait_names} ->
        if Map.has_key?(ctx, entity) do
          current = ctx.__seed_factory_meta__.current_traits[entity] || []

          for name <- trait_names,
              expected_reference(schema, entity, name) not in current,
              do: {entity, name}
        else
          [entity]
        end

      entity ->
        case {Map.fetch(ctx, entity), Enum.find(schema.consumers, &(&1.output == entity))} do
          {:error, _consumer} -> [entity]
          {{:ok, _instance}, nil} -> []
          {{:ok, %{v: seen}}, %{v: required}} when seen === required -> []
          {{:ok, _instance}, _consumer} -> [{:saw, entity}]
        end
    end)
  end

  defp run_step(ctx, step) do
    task =
      Task.async(fn ->
        try do
          case step do
            {:exec, command, args} -> {:ok, SeedFactory.exec(ctx, command, args)}
            {:produce, request} -> {:ok, SeedFactory.produce(ctx, request)}
            {:pre_produce, request} -> {:ok, SeedFactory.pre_produce(ctx, request)}
          end
        rescue
          e -> {:error, e}
        end
      end)

    case Task.yield(task, 4_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, r} -> r
      nil -> :timeout
    end
  end

  # A request pre_produce accepted has to be producible right after it.
  defp run_sequence(ctx, schema) do
    schema.steps
    |> Enum.with_index(1)
    |> Enum.reduce_while({ctx, :ok, nil}, fn {step, index}, {ctx, _outcome, _failed_step} ->
      previous =
        if index > 1 do
          Enum.at(schema.steps, index - 2)
        end

      case {run_step(ctx, step), step, previous} do
        {:timeout, _step, _previous} ->
          {:halt, {ctx, :hang, index}}

        {{:error, _e}, {:produce, request}, {:pre_produce, request}} ->
          {:halt, {ctx, {:silent_missing, [{:pre_produce_accepted, request}]}, index}}

        {{:error, e}, _step, _previous} ->
          {:halt, {ctx, {:raised, e.__struct__}, index}}

        {{:ok, new_ctx}, _step, _previous} ->
          missing =
            case step do
              {:produce, request} -> missing_in_context(new_ctx, request, schema)
              {_operation, _command_or_request, _args} -> []
              {:pre_produce, _request} -> []
            end

          case missing ++ inconsistent_values(new_ctx) do
            [] -> {:cont, {new_ctx, :ok, nil}}
            problems -> {:halt, {new_ctx, {:silent_missing, problems}, index}}
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
            {_ctx, outcome, failed_step} = run_sequence(context, schema)

            [
              {seed,
               Map.merge(schema, %{
                 outcome: outcome,
                 satisfiable: nil,
                 failed_step: failed_step,
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
