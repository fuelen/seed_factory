defmodule SeedFactory.SequencePlanChoiceTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Minimized from rich-seq stress seed 123. The first request has three
    # candidates for :gamma and no other constraint, so the first declared one,
    # :make_alpha_gamma, is the pinned default. The resolution picks
    # :make_beta_gamma instead: the dependency of :make_gamma_from_omega
    # auto-resolves to :make_beta_omega, whose produce-exclusion knocks
    # :make_beta_gamma out of the group and shifts the choice. The second
    # request then cannot get :alpha without producing :gamma a second time
    # and raises EntityAlreadyExistsError. v0.8.2 planned make_alpha_gamma
    # first and make_beta_omega second.
    command :make_alpha_gamma do
      resolve(fn _ -> {:ok, %{alpha: {:ag, :alpha}, gamma: {:ag, :gamma}}} end)

      produce :alpha
      produce :gamma
    end

    command :make_beta_gamma do
      resolve(fn _ -> {:ok, %{beta: {:bg, :beta}, gamma: {:bg, :gamma}}} end)

      produce :beta
      produce :gamma
    end

    command :make_beta_omega do
      resolve(fn _ -> {:ok, %{beta: {:bo, :beta}, omega: {:bo, :omega}}} end)

      produce :beta
      produce :omega
    end

    command :make_gamma_from_omega do
      param :omega, entity: :omega

      resolve(fn _ -> {:ok, %{gamma: {:go, :gamma}}} end)

      produce :gamma
    end
  end

  use SeedFactory.Test, schema: Schema

  test "the first declared candidate wins when nothing narrows the choice", context do
    context = produce(context, [:gamma])

    assert Map.has_key?(context, :alpha)

    context = produce(context, [:alpha, :beta, :gamma, :omega])

    assert Map.has_key?(context, :beta)
    assert Map.has_key?(context, :omega)
  end
end
