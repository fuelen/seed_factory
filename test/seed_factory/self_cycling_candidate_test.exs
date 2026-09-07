defmodule SeedFactory.SelfCyclingCandidateTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Minimized from rich stress seed 182. :make_gamma_omega alone satisfies
    # the request. The other candidate, :make_zeta_omega, needs :beta, and
    # every command producing :beta needs :omega or :zeta back from it, so it
    # is a dead end. The resolution still raises CircularDependencyError
    # [:make_beta_gamma, :make_zeta_omega] instead of taking the first
    # declared, dependency-free candidate as v0.8.2 did.
    command :make_gamma_omega do
      resolve(fn _ -> {:ok, %{gamma: {:go, :gamma}, omega: {:go, :omega}}} end)

      produce :gamma
      produce :omega
    end

    command :make_beta_gamma do
      param :omega, entity: :omega

      resolve(fn _ -> {:ok, %{beta: {:bg, :beta}, gamma: {:bg, :gamma}}} end)

      produce :beta
      produce :gamma
    end

    command :make_zeta_omega do
      param :beta, entity: :beta

      resolve(fn _ -> {:ok, %{zeta: {:zo, :zeta}, omega: {:zo, :omega}}} end)

      produce :zeta
      produce :omega
    end

    command :make_beta_from_zeta do
      param :zeta, entity: :zeta

      resolve(fn _ -> {:ok, %{beta: {:bz, :beta}}} end)

      produce :beta
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a candidate whose dependencies cycle back to it does not block the request", context do
    context = produce(context, [:omega])

    assert Map.has_key?(context, :omega)
  end
end
