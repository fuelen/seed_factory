defmodule SeedFactory.ConditionalOrderingOracleTest do
  use ExUnit.Case, async: false
  @moduletag :stress
  import Bitwise

  # The ordering oracle with a conditional re-applier. The same four commands
  # on one entity with two traits, but :c3 applies :intact only when its
  # generated :enabled is true, declared with an args_pattern the search
  # cannot judge. Every schema is built twice, with the generator returning
  # true and false, so 512 schemas; the model knows the real value and the
  # plan has to agree with it: a plan when an order exists, a refusal before
  # any resolver otherwise, whether the search refuses it or the prediction
  # does once the value is fixed. Each schema is requested in the forward and
  # the reverse order of its outputs.
  #
  #   mix test --only stress test/stress/conditional_ordering_oracle_test.exs

  @orders for a <- 0..3,
              b <- 0..3,
              c <- 0..3,
              d <- 0..3,
              length(Enum.uniq([a, b, c, d])) == 4,
              do: [a, b, c, d]

  # {removed, added} bits per command; :c3 adds :intact only when enabled
  @effects [{1, 0}, {2, 0}, {0, 1}, {0, 2}]

  @tag timeout: 180_000
  test "plans agree with the exhaustive model when one re-applier is conditional" do
    failures =
      for enabled <- [true, false], a <- 0..3, b <- 0..3, c <- 0..3, d <- 0..3, reduce: [] do
        failures ->
          required = [a, b, c, d]
          effects = List.replace_at(@effects, 3, {0, conditional_bits(enabled)})
          expected = Enum.any?(@orders, &valid_order?(&1, required, effects))
          module = Module.concat(__MODULE__, "Case#{enabled}_#{a}_#{b}_#{c}_#{d}")

          commands =
            for {mask, index} <- Enum.with_index(required) do
              traits = for {name, bit} <- [ready: 1, intact: 2], band(mask, bit) != 0, do: name
              {removed, added} = Enum.at(@effects, index)

              """
              command :c#{index} do
                param :enabled, generate: fn -> #{inspect(enabled)} end
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

          Code.compile_string("""
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
            trait :intact, :e do
              exec :c3, args_pattern: %{enabled: true}
            end
          end
          """)

          initial = %{} |> SeedFactory.init(module) |> SeedFactory.exec(:make_e)

          failures =
            Enum.reduce([[0, 1, 2, 3], [3, 2, 1, 0]], failures, fn order, failures ->
              request = Enum.map(order, &String.to_atom("p#{&1}"))
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
                  ] and
                    Process.get(:oracle_executed) == 0
                end

              if accepted do
                failures
              else
                [{enabled, required, order, expected, outcome} | failures]
              end
            end)

          :code.delete(module)
          :code.purge(module)
          failures
      end

    IO.puts("CONDITIONAL_ORACLE: 512 schemas, 1024 requests, #{length(failures)} disagreements")
    assert failures == []
  end

  defp conditional_bits(true), do: 2
  defp conditional_bits(false), do: 0

  defp valid_order?(order, required, effects) do
    Enum.reduce_while(order, 3, fn index, traits ->
      mask = Enum.at(required, index)
      {removed, added} = Enum.at(effects, index)

      if band(traits, mask) == mask do
        {:cont, bor(band(traits, 3 - removed), added)}
      else
        {:halt, :invalid}
      end
    end) != :invalid
  end
end
