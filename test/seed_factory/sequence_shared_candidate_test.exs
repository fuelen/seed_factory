defmodule SeedFactory.SequenceSharedCandidateTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Minimized from rich-seq stress seed 553. In the first request :make_beta
    # is the first declared candidate for :beta, and :omega then comes from
    # :make_omega via :make_gamma_zeta, as v0.8.2 planned. The resolution
    # picks :make_beta_gamma_omega instead, the one candidate shared by both
    # demands. The second request then cannot get :zeta without producing
    # :gamma or :beta a second time and raises EntityAlreadyExistsError.
    command :make_beta do
      resolve(fn _ -> {:ok, %{beta: {:b, :beta}}} end)

      produce :beta
    end

    command :make_beta_gamma_omega do
      resolve(fn _ ->
        {:ok, %{beta: {:bgo, :beta}, gamma: {:bgo, :gamma}, omega: {:bgo, :omega}}}
      end)

      produce :beta
      produce :gamma
      produce :omega
    end

    command :make_gamma_zeta do
      resolve(fn _ -> {:ok, %{gamma: {:gz, :gamma}, zeta: {:gz, :zeta}}} end)

      produce :gamma
      produce :zeta
    end

    command :make_omega do
      param :zeta, entity: :zeta

      resolve(fn _ -> {:ok, %{omega: {:o, :omega}}} end)

      produce :omega
    end

    command :make_beta_zeta do
      resolve(fn _ -> {:ok, %{beta: {:bz, :beta}, zeta: {:bz, :zeta}}} end)

      produce :beta
      produce :zeta
    end
  end

  use SeedFactory.Test, schema: Schema

  test "the first declared candidate wins over one shared by several demands", context do
    context = produce(context, [:beta, :omega])

    assert Map.has_key?(context, :beta)
    assert Map.has_key?(context, :omega)

    context = produce(context, [:beta, :gamma, :omega, :zeta])

    assert Map.has_key?(context, :gamma)
    assert Map.has_key?(context, :zeta)
  end
end
