defmodule SeedFactory.TraitDependencyCommitTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :make_alpha_from_gamma needs :gamma with :tagged, which only
    # :make_gamma_tagged adds. The early resolution of the :gamma candidates
    # in favour of :make_gamma_omega rejects :make_gamma_tagged, and
    # :make_alpha_from_gamma has already been made conflict-free before its
    # parameters were collected, so the collector fallback (drop it, :alpha
    # has another candidate) never fires and the request raises
    # TraitResolutionError. v0.8.2 planned
    # make_omega -> make_beta -> make_gamma_tagged -> make_alpha_from_gamma.
    command :make_omega do
      resolve(fn _ -> {:ok, %{omega: {:o, :omega}}} end)

      produce :omega
    end

    command :make_beta do
      resolve(fn _ -> {:ok, %{beta: {:b, :beta}}} end)

      produce :beta
    end

    command :make_gamma_omega do
      resolve(fn _ -> {:ok, %{gamma: {:go, :gamma}, omega: {:go, :omega}}} end)

      produce :gamma
      produce :omega
    end

    command :make_gamma_tagged do
      resolve(fn _ -> {:ok, %{gamma: {:gt, :gamma}}} end)

      produce :gamma
    end

    command :make_alpha_omega do
      resolve(fn _ -> {:ok, %{alpha: {:ao, :alpha}, omega: {:ao, :omega}}} end)

      produce :alpha
      produce :omega
    end

    command :make_alpha_from_gamma do
      param :gamma, entity: :gamma, with_traits: [:tagged]

      resolve(fn _ -> {:ok, %{alpha: {:ag, :alpha}}} end)

      produce :alpha
    end

    trait :tagged, :gamma do
      exec :make_gamma_tagged
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a trait dependency rejected by an early resolution does not fail the request", context do
    context = produce(context, [:alpha, :beta, :gamma, :omega])

    assert Map.has_key?(context, :alpha)
    assert Map.has_key?(context, :beta)
    assert Map.has_key?(context, :gamma)
    assert Map.has_key?(context, :omega)
  end
end
