defmodule SeedFactory.StressDumpTest do
  use ExUnit.Case, async: false
  @moduletag :stress

  # Runs the same deterministic random cases and dumps per-seed outcomes to a
  # file so two library versions can be compared.

  @n_cases 400

  defp gen_schema(seed) do
    :rand.seed(:exsss, {seed, seed * 7 + 1, seed * 13 + 5})

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

    request_size = Enum.random(1..n_entities)
    request = entities |> Enum.shuffle() |> Enum.take(request_size) |> Enum.sort()

    {produced_by_command, request}
  end

  defp build_module(seed, produced_by_command) do
    mod = :"Elixir.StressSchema#{seed}"

    commands_code =
      produced_by_command
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {produced, i} ->
        result_map =
          produced
          |> Enum.map_join(", ", fn e -> "#{e}: {:c#{i}, #{inspect(e)}}" end)

        produces = Enum.map_join(produced, "\n", fn e -> "    produce #{inspect(e)}" end)

        """
          command :c#{i} do
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
    mod
  end

  defp valid_plan_exists?(produced_by_command, request) do
    n = length(produced_by_command)
    indexed = Enum.with_index(produced_by_command)

    Enum.any?(0..(Integer.pow(2, n) - 1), fn mask ->
      chosen =
        for {produced, i} <- indexed, Bitwise.band(mask, Bitwise.bsl(1, i)) != 0, do: produced

      all = List.flatten(chosen)
      Enum.uniq(all) == all and Enum.all?(request, &(&1 in all))
    end)
  end

  test "dump outcomes" do
    out_path = System.get_env("STRESS_OUT")

    results =
      Enum.map(1..@n_cases, fn seed ->
        {produced_by_command, request} = gen_schema(seed)
        mod = build_module(seed, produced_by_command)

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

        satisfiable = valid_plan_exists?(produced_by_command, request)

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

        {seed,
         %{
           outcome: outcome,
           satisfiable: satisfiable,
           producers: produced_by_command,
           request: request
         }}
      end)

    if out_path do
      File.write!(out_path, :erlang.term_to_binary(Map.new(results)))
    end

    assert SeedFactory.StressOutcomes.alarming(results) == []
  end
end
