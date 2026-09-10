defmodule SeedFactory.OrderingOracleTest do
  use ExUnit.Case, async: false
  @moduletag :stress
  import Bitwise

  # The ordering of trait reads and losses on one entity, checked against an
  # independent model. e carries two traits, :ready and :intact, as bits of
  # its value. Four commands update e: :c0 strips :ready, :c1 strips :intact,
  # :c2 applies :ready, :c3 applies :intact, and each may demand any subset of
  # the two traits with with_traits, which gives 4^4 = 256 schemas. For every
  # schema the model walks all 24 execution orders of the four commands and
  # says whether one of them satisfies every demand; produce is then asked
  # for the four outputs in all 24 request orders and has to agree: a plan
  # whenever one exists, a refusal before any resolver runs otherwise. The
  # resolvers check the traits they read on the value itself, so a plan that
  # hands a command the wrong state fails inside the resolver.
  #
  #   mix test --only stress test/stress/ordering_oracle_test.exs

  @orders for a <- 0..3,
              b <- 0..3,
              c <- 0..3,
              d <- 0..3,
              length(Enum.uniq([a, b, c, d])) == 4,
              do: [a, b, c, d]

  # {removed, added} bits per command
  @effects [{1, 0}, {2, 0}, {0, 1}, {0, 2}]

  @tag timeout: 180_000
  test "plans agree with the exhaustive model of four commands on one entity" do
    failures =
      for a <- 0..3, b <- 0..3, c <- 0..3, d <- 0..3, reduce: [] do
        failures ->
          required = [a, b, c, d]
          expected = Enum.any?(@orders, &valid_order?(&1, required))
          module = Module.concat(__MODULE__, "Case#{a}_#{b}_#{c}_#{d}")

          commands =
            for {mask, index} <- Enum.with_index(required) do
              traits = for {name, bit} <- [ready: 1, intact: 2], band(mask, bit) != 0, do: name
              {removed, added} = Enum.at(@effects, index)

              """
              command :c#{index} do
                param :e, entity: :e, with_traits: #{inspect(traits)}
                resolve(fn args ->
                  Process.put(:oracle_executed, Process.get(:oracle_executed, 0) + 1)

                  if Bitwise.band(args.e, #{mask}) != #{mask} do
                    raise "invalid read"
                  end

                  {:ok, %{e: Bitwise.bor(Bitwise.band(args.e, #{3 - removed}), #{added}), p#{index}: args.e}}
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
              exec :c3
            end
          end
          """)

          initial = %{} |> SeedFactory.init(module) |> SeedFactory.exec(:make_e)

          failures =
            Enum.reduce(@orders, failures, fn order, failures ->
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
                  outcome == {:error, SeedFactory.TraitResolutionError} and
                    Process.get(:oracle_executed) == 0
                end

              if accepted do
                failures
              else
                [{required, order, expected, outcome} | failures]
              end
            end)

          :code.delete(module)
          :code.purge(module)
          failures
      end

    IO.puts("ORDERING_ORACLE: 256 schemas, 6144 requests, #{length(failures)} disagreements")
    assert failures == []
  end

  defp valid_order?(order, required) do
    Enum.reduce_while(order, 3, fn index, traits ->
      mask = Enum.at(required, index)
      {removed, added} = Enum.at(@effects, index)

      if band(traits, mask) == mask do
        {:cont, bor(band(traits, 3 - removed), added)}
      else
        {:halt, :invalid}
      end
    end) != :invalid
  end
end
