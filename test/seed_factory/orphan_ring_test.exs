defmodule SeedFactory.OrphanRingTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Same ring as demander_cycle_test, but :cross_checker_alt is declared
    # first, so it wins the :t_out group and :cross_checker is removed. The
    # ring it pulled in keeps itself alive through the mutual required_by and
    # leaks into the topological sort.
    command :cross_checker_alt do
      resolve(fn _ -> {:ok, %{t_out: :alt}} end)

      produce :t_out
    end

    command :make_res do
      resolve(fn _ -> {:ok, %{res: :res, other: :other_res}} end)

      produce :res
      produce :other
    end

    command :other_alt do
      resolve(fn _ -> {:ok, %{other: :other_alt}} end)

      produce :other
    end

    command :make_a_plain do
      resolve(fn _ -> {:ok, %{ring_a: :a_plain}} end)

      produce :ring_a
    end

    command :make_b_plain do
      resolve(fn _ -> {:ok, %{ring_b: :b_plain}} end)

      produce :ring_b
    end

    command :ring_a_cyc do
      param :ring_b, entity: :ring_b
      param :res, entity: :res

      resolve(fn args -> {:ok, %{ring_a: {:a, args.ring_b}, side_a: :side_a}} end)

      produce :ring_a
      produce :side_a
    end

    command :ring_b_cyc do
      param :ring_a, entity: :ring_a

      resolve(fn args -> {:ok, %{ring_b: {:b, args.ring_a}, side_b: :side_b}} end)

      produce :ring_b
      produce :side_b
    end

    command :cross_checker do
      param :side_a, entity: :side_a
      param :side_b, entity: :side_b

      resolve(fn _ -> {:ok, %{t_out: :checked}} end)

      produce :t_out
    end
  end

  use SeedFactory.Test, schema: Schema

  @tag timeout: 5_000
  test "a ring pulled in by a losing candidate does not fail the plan", context do
    context = produce(context, [:other, :t_out])

    assert context.t_out == :alt
    assert Map.has_key?(context, :other)
  end
end
