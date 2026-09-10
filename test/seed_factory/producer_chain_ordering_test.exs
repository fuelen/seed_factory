# A chain of eight producers of :e, each after the deleter of the previous
# instance through its own output: make_1 → delete_1 → make_2 → … → make_8.
# The dependencies leave exactly one interleave order; the search has to find
# it without trying the 8! × 7! orders first.
chain_size = 8

commands =
  for index <- 1..chain_size do
    dependency =
      if index == 1 do
        ""
      else
        "param :d, entity: :d#{index - 1}"
      end

    deleter =
      if index == chain_size do
        ""
      else
        """
        command :delete_#{index} do
          param :e, entity: :e
          param :p, entity: :p#{index}
          resolve(fn _ -> {:ok, %{d#{index}: #{index}}} end)
          delete :e
          produce :d#{index}
        end
        """
      end

    """
    command :make_#{index} do
      #{dependency}
      resolve(fn _ -> {:ok, %{e: #{index}, p#{index}: #{index}}} end)
      produce :e
      produce :p#{index}
    end
    #{deleter}
    """
  end

Code.compile_string("""
defmodule SeedFactory.ProducerChainOrderingTest.Schema do
  use SeedFactory.Schema
  #{Enum.join(commands, "\n")}
end
""")

defmodule SeedFactory.ProducerChainOrderingTest do
  use ExUnit.Case, async: true

  use SeedFactory.Test, schema: __MODULE__.Schema

  @tag timeout: 10_000
  test "a long chain of producers and deleters is ordered without enumerating every order",
       context do
    context = produce(context, Enum.map(1..8, &:"p#{&1}"))

    assert context.e == 8
    assert Enum.map(1..8, &Map.fetch!(context, :"p#{&1}")) == Enum.to_list(1..8)
  end
end
