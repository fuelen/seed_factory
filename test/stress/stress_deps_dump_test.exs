defmodule SeedFactory.StressDepsDumpTest do
  use ExUnit.Case, async: false
  @moduletag :stress

  # Schemas with entity params (dependencies between commands).
  # Command ci may only depend on entities all of whose producers have a
  # smaller index, which keeps the schema compilable; seeds that still trip
  # the DSL cycle check are skipped.

  @n_cases 400

  defp gen_schema(seed) do
    :rand.seed(:exsss, {seed * 3 + 11, seed * 7 + 1, seed * 13 + 5})

    n_entities = Enum.random(3..6)
    n_commands = Enum.random(3..6)

    entities = Enum.map(1..n_entities, &:"e#{&1}")

    produced_by_command =
      Enum.map(1..n_commands, fn _ ->
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
          List.update_at(acc, rem(i, length(produced_by_command)), &Enum.uniq([e | &1]))
        end
      end)

    # deps: command i may depend on entities whose every producer has index < i
    deps_by_command =
      produced_by_command
      |> Enum.with_index()
      |> Enum.map(fn {_produced, i} ->
        allowed =
          Enum.filter(entities, fn e ->
            producers =
              produced_by_command
              |> Enum.with_index()
              |> Enum.filter(fn {p, _j} -> e in p end)
              |> Enum.map(&elem(&1, 1))

            producers != [] and Enum.all?(producers, &(&1 < i))
          end)

        k = Enum.random(0..min(2, length(allowed)))
        allowed |> Enum.shuffle() |> Enum.take(k) |> Enum.sort()
      end)

    request_size = Enum.random(1..n_entities)
    request = entities |> Enum.shuffle() |> Enum.take(request_size) |> Enum.sort()

    {produced_by_command, deps_by_command, request}
  end

  defp build_module(seed, produced_by_command, deps_by_command) do
    mod = :"Elixir.StressDepsSchema#{seed}"

    commands_code =
      Enum.zip(produced_by_command, deps_by_command)
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {{produced, deps}, i} ->
        result_map =
          produced
          |> Enum.map_join(", ", fn e -> "#{e}: {:c#{i}, #{inspect(e)}}" end)

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

    code = """
    defmodule #{inspect(mod)} do
      use SeedFactory.Schema
    #{commands_code}
    end
    """

    Code.compile_string(code)
    {:ok, mod}
  rescue
    _e in Spark.Error.DslError -> :skip
  end

  defp valid_plan_exists?(produced_by_command, deps_by_command, request) do
    n = length(produced_by_command)

    Enum.any?(0..(Integer.pow(2, n) - 1), fn mask ->
      chosen_idx = for i <- 0..(n - 1), Bitwise.band(mask, Bitwise.bsl(1, i)) != 0, do: i

      produced = Enum.flat_map(chosen_idx, &Enum.at(produced_by_command, &1))
      deps = Enum.flat_map(chosen_idx, &Enum.at(deps_by_command, &1))

      Enum.uniq(produced) == produced and
        Enum.all?(request, &(&1 in produced)) and
        Enum.all?(deps, &(&1 in produced))
    end)
  end

  test "dump outcomes" do
    out_path = System.get_env("STRESS_OUT")

    results =
      Enum.flat_map(1..@n_cases, fn seed ->
        {produced_by_command, deps_by_command, request} = gen_schema(seed)

        case build_module(seed, produced_by_command, deps_by_command) do
          :skip ->
            []

          {:ok, mod} ->
            context = SeedFactory.Context.init(%{}, mod)

            task =
              Task.async(fn ->
                try do
                  {:ok, SeedFactory.produce(context, request)}
                rescue
                  e -> {:error, e}
                end
              end)

            result =
              case Task.yield(task, 4_000) || Task.shutdown(task, :brutal_kill) do
                {:ok, r} -> r
                nil -> :timeout
              end

            satisfiable = valid_plan_exists?(produced_by_command, deps_by_command, request)

            outcome =
              case result do
                :timeout ->
                  :hang

                {:ok, ctx} ->
                  missing = Enum.reject(request, &Map.has_key?(ctx, &1))
                  if missing == [], do: :ok, else: {:silent_missing, missing}

                {:error, e} ->
                  {:raised, e.__struct__}
              end

            [
              {seed,
               %{
                 outcome: outcome,
                 satisfiable: satisfiable,
                 producers: produced_by_command,
                 deps: deps_by_command,
                 request: request
               }}
            ]
        end
      end)

    if out_path do
      File.write!(out_path, :erlang.term_to_binary(Map.new(results)))
    end

    assert SeedFactory.StressOutcomes.alarming(results) == []
  end
end
