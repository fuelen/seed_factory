defmodule SeedFactory.DependentOrderingOracleTest do
  use ExUnit.Case, async: false
  @moduletag :stress
  import Bitwise

  # The ordering oracle with dependencies between the commands. The same
  # entity e with :ready and :intact; :c0 strips :ready, :c1 strips :intact,
  # :c2 applies :ready for sure and :c3 applies :ready when its generated
  # :enabled is true. Every command may additionally require the output of one
  # other command, so a reader can be forced after the command stripping its
  # trait and the plan has to shelter it with :c2 or :c3, the certain one
  # first. By default exactly one command demands traits and the family is
  # exhaustive over the acyclic dependency patterns and both generator values;
  # ORACLE_FULL=1 runs every demand combination (tens of thousands of
  # schemas, tens of minutes). The model knows the generated value and
  # enumerates the 24 orders; produce has to agree, the refusal coming
  # before any resolver.
  #
  #   mix test --only stress test/stress/dependent_ordering_oracle_test.exs
  #   ORACLE_FULL=1 mix test --only stress --timeout 3600000 test/stress/dependent_ordering_oracle_test.exs

  @orders for a <- 0..3,
              b <- 0..3,
              c <- 0..3,
              d <- 0..3,
              length(Enum.uniq([a, b, c, d])) == 4,
              do: [a, b, c, d]

  # the command stripping each trait bit
  @removers %{1 => 0, 2 => 1}

  @tag timeout: 3_600_000
  test "plans agree with the exhaustive model when dependencies force the order" do
    combos = combos(System.get_env("ORACLE_FULL") == "1")

    failures =
      for {deps, masks} <- combos, reduce: [] do
        failures ->
          module =
            Module.concat(
              __MODULE__,
              "Case#{Enum.join(Enum.map(deps, &inspect/1), "_")}_#{Enum.join(masks)}"
            )

          Code.compile_string(schema_source(module, deps, masks))
          initial = %{} |> SeedFactory.init(module) |> SeedFactory.exec(:make_e)

          failures =
            for enabled <- [true, false],
                order <- [[0, 1, 2, 3], [3, 2, 1, 0]],
                reduce: failures do
              failures ->
                expected = Enum.any?(@orders, &valid_order?(&1, masks, deps, enabled))
                request = Enum.map(order, &String.to_atom("p#{&1}"))
                Process.put(:oracle_enabled, enabled)
                Process.put(:oracle_executed, 0)

                outcome =
                  try do
                    result = SeedFactory.produce(initial, request)

                    if Enum.all?(request, &Map.has_key?(result, &1)) do
                      :ok
                    else
                      :missing_output
                    end
                  rescue
                    error -> {:error, error.__struct__}
                  end

                accepted =
                  if expected do
                    outcome == :ok
                  else
                    outcome in [
                      {:error, SeedFactory.TraitResolutionError},
                      {:error, SeedFactory.MissingRequestedTraitError}
                    ] and Process.get(:oracle_executed) == 0
                  end

                if accepted do
                  failures
                else
                  [{deps, masks, enabled, order, expected, outcome} | failures]
                end
            end

          purge(module)
          failures
      end

    IO.puts(
      "DEPENDENT_ORACLE: #{length(combos)} schemas, #{4 * length(combos)} requests, " <>
        "#{length(failures)} disagreements"
    )

    assert failures == []
  end

  # Thousands of generated schemas exhaust the literal area of the VM unless
  # each module leaves it once its requests are done: deleting makes the code
  # old, purging releases it.
  defp purge(module) do
    :code.delete(module)
    :code.purge(module)
  end

  # Every acyclic pattern of one optional dependency per command, with the
  # demand masks that put some reader after the remover of a trait it needs.
  defp combos(full?) do
    patterns =
      for a <- [nil, 1, 2, 3],
          b <- [nil, 0, 2, 3],
          c <- [nil, 0, 1, 3],
          d <- [nil, 0, 1, 2],
          deps = [a, b, c, d],
          Enum.all?(0..3, &(not reaches?(deps, &1, &1))),
          do: deps

    masks =
      if full? do
        for a <- 0..3, b <- 0..3, c <- 0..3, d <- 0..3, do: [a, b, c, d]
      else
        for index <- 0..3, mask <- 1..3, do: List.replace_at([0, 0, 0, 0], index, mask)
      end

    for deps <- patterns, masks <- masks, forced_read?(deps, masks), do: {deps, masks}
  end

  defp forced_read?(deps, masks) do
    Enum.any?(Enum.with_index(masks), fn {mask, index} ->
      Enum.any?([1, 2], &(band(mask, &1) != 0 and reaches?(deps, index, @removers[&1])))
    end)
  end

  # The commands the command depends on, following the single dependency of
  # each; a cycle is cut after four steps.
  defp reaches?(deps, from, to) do
    Enum.reduce_while(1..4, Enum.at(deps, from), fn _, current ->
      cond do
        current == nil -> {:halt, false}
        current == to -> {:halt, true}
        true -> {:cont, Enum.at(deps, current)}
      end
    end) == true
  end

  defp valid_order?(order, masks, deps, enabled) do
    Enum.reduce_while(order, {3, []}, fn index, {traits, done} ->
      mask = Enum.at(masks, index)
      dependency = Enum.at(deps, index)
      {removed, added} = effect(index, enabled)

      if band(traits, mask) == mask and (dependency == nil or dependency in done) do
        {:cont, {bor(band(traits, 3 - removed), added), [index | done]}}
      else
        {:halt, :invalid}
      end
    end) != :invalid
  end

  defp effect(0, _enabled), do: {1, 0}
  defp effect(1, _enabled), do: {2, 0}
  defp effect(2, _enabled), do: {0, 1}
  defp effect(3, true), do: {0, 1}
  defp effect(3, false), do: {0, 0}

  defp schema_source(module, deps, masks) do
    commands =
      for {mask, index} <- Enum.with_index(masks) do
        traits = for {name, bit} <- [ready: 1, intact: 2], band(mask, bit) != 0, do: name
        {removed, added} = effect(index, true)

        dependency =
          case Enum.at(deps, index) do
            nil -> ""
            other -> "param :p#{other}, entity: :p#{other}"
          end

        """
        command :c#{index} do
          #{dependency}
          param :enabled, generate: fn -> Process.get(:oracle_enabled) end
          param :e, entity: :e, with_traits: #{inspect(traits)}
          resolve(fn args ->
            Process.put(:oracle_executed, Process.get(:oracle_executed, 0) + 1)

            if Bitwise.band(args.e, #{mask}) != #{mask} do
              raise "invalid read"
            end

            added =
              if #{index} == 3 and not args.enabled do
                0
              else
                #{added}
              end

            {:ok, %{e: Bitwise.bor(Bitwise.band(args.e, #{3 - removed}), added), p#{index}: args.e}}
          end)
          update :e
          produce :p#{index}
        end
        """
      end

    """
    defmodule #{inspect(module)} do
      use SeedFactory.Schema
      command :make_e do
        resolve(fn _ -> {:ok, %{e: 3}} end)
        produce :e
      end
      #{Enum.join(commands, "\n")}
      trait :ready, :e do
        exec :make_e
      end
      trait :intact, :e do
        exec :make_e
      end
      trait :lost_ready, :e do
        from :ready
        exec :c0
      end
      trait :lost_intact, :e do
        from :intact
        exec :c1
      end
      trait :ready, :e do
        exec :c2
      end
      trait :ready, :e do
        exec :c3, args_pattern: %{enabled: true}
      end
    end
    """
  end
end
