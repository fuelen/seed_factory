defmodule SeedFactory.UnproducibleEntityTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :cmd_c sits in two conflict groups (:alpha and :hotel), so the demand for
    # :beta narrows the :alpha group without removing :cmd_c. :gamma is
    # producible only by :cmd_c, and that demand resolves the groups in favour
    # of :cmd_c, killing every command able to produce :beta.
    command :cmd_a do
      resolve(fn _ -> {:ok, %{alpha: :alpha_a, beta: :beta_a}} end)

      produce :alpha
      produce :beta
    end

    command :cmd_b do
      resolve(fn _ -> {:ok, %{alpha: :alpha_b, beta: :beta_b}} end)

      produce :alpha
      produce :beta
    end

    command :cmd_c do
      resolve(fn _ -> {:ok, %{alpha: :alpha_c, hotel: :hotel_c, gamma: :gamma_c}} end)

      produce :alpha
      produce :hotel
      produce :gamma
    end

    command :cmd_d do
      resolve(fn _ -> {:ok, %{hotel: :hotel_d}} end)

      produce :hotel
    end

    command :use_beta do
      param :beta, entity: :beta, with_traits: [:gamma_checked]

      resolve(fn args -> {:ok, %{beta_report: {:report, args.beta}}} end)

      produce :beta_report
    end

    # Takes only :gamma, so the demand for :gamma is registered strictly after
    # the demand for the :beta producers within the same requirements pass.
    command :cross_check_beta do
      param :gamma, entity: :gamma

      resolve(fn _ -> {:ok, %{beta: :beta_checked}} end)

      update :beta
    end

    trait :gamma_checked, :beta do
      exec :cross_check_beta
    end

    command :use_gamma do
      param :gamma, entity: :gamma

      resolve(fn args -> {:ok, %{gamma_report: {:report, args.gamma}}} end)

      produce :gamma_report
    end
  end

  use SeedFactory.Test, schema: Schema

  test "produce raises when a requested entity loses every command able to produce it",
       context do
    # Was: produce silently returned a context without the requested :beta.
    assert_raise SeedFactory.UnproducibleEntityError,
                 "cannot produce entity :beta: all commands able to produce it " <>
                   "were rejected during conflict resolution: [:cmd_a, :cmd_b]",
                 fn ->
                   produce(context, [:alpha, :hotel, :beta, :gamma_report])
                 end
  end

  test "raises when a dependency of a planned command loses every command able to produce it",
       context do
    # The same conflict, but :beta is demanded by :use_beta. The with_traits
    # chain registers the demand for the :beta producers first, then the
    # :gamma_checked exec command demands :gamma, which forces :cmd_c and kills
    # the narrowed subset. Was: EntityNotFoundError far from the cause, when
    # :cross_check_beta tried to update the never-produced :beta.
    assert_raise SeedFactory.UnproducibleEntityError,
                 "cannot produce entity :beta required by :use_beta: all commands able to " <>
                   "produce it were rejected during conflict resolution: [:cmd_a, :cmd_b]",
                 fn ->
                   produce(context, [:alpha, :hotel, :beta_report])
                 end
  end
end
