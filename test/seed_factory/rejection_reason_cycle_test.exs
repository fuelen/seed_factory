defmodule SeedFactory.RejectionReasonCycleTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Pins the cycle line of the rejection reasons. :make_a is chosen for
    # :alpha and requires :make_d through :gamma, so :make_d's own demand for
    # :shared cannot reuse :make_a, while :make_shared_alt dies on a produce
    # conflict. The relaxed pass tolerates the cycle but dies on
    # :make_impossible's produce conflict, so the strict dead end is the
    # raised one.
    command :make_shared_alt do
      resolve(fn _ -> {:ok, %{shared: :shared_alt, collide: :collide_alt}} end)

      produce :shared
      produce :collide
    end

    command :make_a do
      param :gamma, entity: :gamma

      resolve(fn _ -> {:ok, %{alpha: :alpha, shared: :shared}} end)

      produce :alpha
      produce :shared
    end

    command :make_d do
      param :shared, entity: :shared

      resolve(fn _ -> {:ok, %{gamma: :gamma, collide: :collide_d}} end)

      produce :gamma
      produce :collide
    end

    command :make_impossible do
      resolve(fn _ -> {:ok, %{impossible: :impossible, collide: :collide_b}} end)

      produce :impossible
      produce :collide
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a chosen command blocked from reuse gets the cycle reason line", context do
    assert_raise SeedFactory.UnproducibleEntityError,
                 "cannot produce entity :shared required by :make_d: no candidate command fits the plan\n" <>
                   "- :make_shared_alt also produces :shared, already produced by :make_a in this plan\n" <>
                   "- :make_a transitively requires :make_d, which would form a cycle",
                 fn ->
                   produce(context, [:alpha, :impossible])
                 end
  end
end
