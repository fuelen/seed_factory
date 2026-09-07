defmodule SeedFactory.ExistingGroupDemandTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # The demand for :delta lands on the already existing exclusion group of
    # its two producers and must be recorded there. The request is
    # unsatisfiable (no command subset covers all five entities without
    # producing something twice), so produce must raise instead of returning a
    # context without :delta.
    command :make_three do
      resolve(fn _ -> {:ok, %{gamma: :gamma_a, delta: :delta_a, epsilon: :epsilon_a}} end)

      produce :gamma
      produce :delta
      produce :epsilon
    end

    command :make_four do
      resolve(fn _ ->
        {:ok, %{alpha: :alpha_b, beta: :beta_b, gamma: :gamma_b, epsilon: :epsilon_b}}
      end)

      produce :alpha
      produce :beta
      produce :gamma
      produce :epsilon
    end

    command :make_trio do
      resolve(fn _ -> {:ok, %{alpha: :alpha_c, beta: :beta_c, gamma: :gamma_c}} end)

      produce :alpha
      produce :beta
      produce :gamma
    end

    command :make_mix do
      resolve(fn _ -> {:ok, %{beta: :beta_d, delta: :delta_d, epsilon: :epsilon_d}} end)

      produce :beta
      produce :delta
      produce :epsilon
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a demand landing on an existing group is remembered", context do
    assert_raise SeedFactory.UnproducibleEntityError, fn ->
      produce(context, [:alpha, :beta, :gamma, :delta, :epsilon])
    end
  end
end
