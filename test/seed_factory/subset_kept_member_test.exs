defmodule SeedFactory.SubsetKeptMemberTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Declaration order matters: :make_combo is the first producer of :alpha and
    # sits in two conflict groups (:alpha and :gamma), so a later demand for the
    # {:make_pair_one, :make_pair_two} subset cannot remove it from the graph.
    command :make_combo do
      resolve(fn _ -> {:ok, %{alpha: :alpha_combo, gamma: :gamma_combo}} end)

      produce :alpha
      produce :gamma
    end

    command :make_pair_one do
      resolve(fn _ -> {:ok, %{alpha: :alpha_one, beta: :beta_one}} end)

      produce :alpha
      produce :beta
    end

    command :make_pair_two do
      resolve(fn _ -> {:ok, %{alpha: :alpha_two, beta: :beta_two}} end)

      produce :alpha
      produce :beta
    end

    command :make_gamma do
      resolve(fn _ -> {:ok, %{gamma: :gamma_solo}} end)

      produce :gamma
    end

    command :use_beta do
      param :beta, entity: :beta

      resolve(fn args -> {:ok, %{result: {:result, args.beta}}} end)

      produce :result
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a demand narrowed to a subset survives head-order conflict resolution", context do
    # The request order builds the :alpha and :gamma groups before the demand
    # from :use_beta narrows the :alpha group to the pair producers.
    context = produce(context, [:alpha, :gamma, :result])

    assert %{alpha: _, beta: beta, gamma: _, result: {:result, beta}} = context
  end

  test "the narrowed demand survives regardless of the request order", context do
    context = produce(context, [:result, :gamma, :alpha])

    assert %{alpha: _, beta: beta, gamma: _, result: {:result, beta}} = context
  end
end
