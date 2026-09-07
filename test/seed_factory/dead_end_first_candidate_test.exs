defmodule SeedFactory.DeadEndFirstCandidateTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Minimized from rich stress seed 225. The first declared candidate for
    # :alpha, :make_alpha_gamma, needs :beta. Every command producing :beta
    # either needs :gamma, which would then have to come from
    # :make_alpha_gamma itself (a cycle), or produces :gamma as well (a second
    # command producing it). So :alpha has to come from :make_alpha. The
    # resolution commits to the first candidate and raises
    # CircularDependencyError [:make_alpha_gamma, :make_beta]. v0.8.2 planned
    # make_gamma -> make_alpha -> make_beta.
    command :make_gamma do
      resolve(fn _ -> {:ok, %{gamma: {:g, :gamma}}} end)

      produce :gamma
    end

    command :make_alpha_gamma do
      param :beta, entity: :beta

      resolve(fn _ -> {:ok, %{alpha: {:ag, :alpha}, gamma: {:ag, :gamma}}} end)

      produce :alpha
      produce :gamma
    end

    command :make_alpha do
      resolve(fn _ -> {:ok, %{alpha: {:a, :alpha}}} end)

      produce :alpha
    end

    command :make_beta do
      param :gamma, entity: :gamma

      resolve(fn _ -> {:ok, %{beta: {:b, :beta}}} end)

      produce :beta
    end

    command :make_beta_gamma do
      resolve(fn _ -> {:ok, %{beta: {:bg, :beta}, gamma: {:bg, :gamma}}} end)

      produce :beta
      produce :gamma
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a first declared candidate that is a dead end gives way to the next one", context do
    context = produce(context, [:alpha, :beta, :gamma])

    assert Map.has_key?(context, :alpha)
    assert Map.has_key?(context, :beta)
    assert Map.has_key?(context, :gamma)
  end
end
