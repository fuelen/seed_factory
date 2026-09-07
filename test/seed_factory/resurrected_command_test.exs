defmodule SeedFactory.ResurrectedCommandTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # The demand for :beta resolves the :alpha group in favour of
    # :make_alpha_and_beta and rejects :make_alpha_and_gamma. The demand for
    # :gamma then brings the rejected command back in a fresh group that has
    # to remember the exclusion over :alpha. :make_gamma must be declared
    # after :make_alpha_and_gamma, so the head-order resolution of the fresh
    # group alone would pick the wrong member.
    command :make_alpha_and_beta do
      resolve(fn _ -> {:ok, %{alpha: :alpha_one, beta: :beta_one}} end)

      produce :alpha
      produce :beta
    end

    command :make_alpha_and_gamma do
      resolve(fn _ -> {:ok, %{alpha: :alpha_two, gamma: :gamma_two}} end)

      produce :alpha
      produce :gamma
    end

    command :make_gamma do
      resolve(fn _ -> {:ok, %{gamma: :gamma_solo}} end)

      produce :gamma
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a resurrected command regains its exclusions", context do
    context = produce(context, [:alpha, :beta, :gamma])

    assert %{alpha: :alpha_one, beta: :beta_one, gamma: :gamma_solo} = context
  end
end
