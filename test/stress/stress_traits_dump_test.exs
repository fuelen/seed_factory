defmodule SeedFactory.StressTraitsDumpTest do
  use ExUnit.Case, async: false
  @moduletag :stress

  # Schemas with traits (creation and from-transitions, duplicate
  # declarations of a name), update commands, with_traits params, delete
  # commands, and requests that ask for traits. Satisfiability is not
  # computed: the oracle is purely differential.

  @n_cases (System.get_env("STRESS_N") || "400") |> String.to_integer()

  defp gen_schema(seed) do
    :rand.seed(:exsss, {seed * 5 + 3, seed * 11 + 7, seed * 17 + 13})

    n_entities = Enum.random(2..4)
    entities = Enum.map(1..n_entities, &:"e#{&1}")

    n_producers = Enum.random(2..4)

    produced_by_command =
      Enum.map(1..n_producers, fn _ ->
        k = Enum.random(1..n_entities)
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

    n_updaters = Enum.random(1..3)
    updated_by_command = Enum.map(1..n_updaters, fn _ -> Enum.random(entities) end)

    deleter =
      if :rand.uniform() < 0.3 and n_entities >= 2 do
        victim = Enum.random(entities)
        %{victim: victim, product: Enum.random(entities -- [victim])}
      end

    n_traits = Enum.random(1..4)

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
              with true <- :rand.uniform() < 0.25,
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

    with_traits_by_updater =
      Enum.map(1..n_updaters, fn idx ->
        entity = Enum.at(updated_by_command, idx - 1)
        names = Map.get(trait_names_by_entity, entity, [])

        if names != [] and :rand.uniform() < 0.3 do
          [Enum.random(names)]
        else
          []
        end
      end)

    request_entities =
      entities |> Enum.shuffle() |> Enum.take(Enum.random(1..n_entities)) |> Enum.sort()

    request =
      Enum.map(request_entities, fn e ->
        names = Map.get(trait_names_by_entity, e, [])

        if names != [] and :rand.uniform() < 0.5 do
          {e, names |> Enum.shuffle() |> Enum.take(Enum.random(1..2)) |> Enum.sort()}
        else
          e
        end
      end)

    %{
      producers: produced_by_command,
      updaters: updated_by_command,
      with_traits: with_traits_by_updater,
      deleter: deleter,
      traits: traits,
      request: request
    }
  end

  defp build_module(seed, schema) do
    mod = :"Elixir.StressTraitsSchema#{seed}"

    producers_code =
      schema.producers
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {produced, i} ->
        result_map = Enum.map_join(produced, ", ", fn e -> "#{e}: {:c#{i}, #{inspect(e)}}" end)
        produces = Enum.map_join(produced, "\n", fn e -> "    produce #{inspect(e)}" end)

        """
          command :c#{i} do
            resolve(fn _ -> {:ok, %{#{result_map}}} end)
        #{produces}
          end
        """
      end)

    updaters_code =
      schema.updaters
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {entity, i} ->
        with_traits =
          case Enum.at(schema.with_traits, i - 1) do
            [] -> ""
            names -> ", with_traits: #{inspect(names)}"
          end

        """
          command :u#{i} do
            param #{inspect(entity)}, entity: #{inspect(entity)}#{with_traits}
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
              param #{inspect(victim)}, entity: #{inspect(victim)}
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
                  {:ok, SeedFactory.produce(context, schema.request)}
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
                  # A requested entity consumed by a deleting command of the
                  # plan is documented behaviour (see the draft_project/email
                  # suite test), not a silently incomplete context.
                  victim = schema.deleter && schema.deleter.victim

                  case missing_in_context(ctx, schema.request) do
                    [] ->
                      :ok

                    missing ->
                      if Enum.all?(missing, &(&1 == victim)) do
                        {:consumed, missing}
                      else
                        {:silent_missing, missing}
                      end
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
