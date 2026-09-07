defmodule SeedFactory.HeadOrderSafetyTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :make_pair heads the first unresolved group at resolution time, yet
    # resolving in its favour would remove every command able to produce
    # :alpha. The safe choice is :make_all_one, which covers everything.
    command :make_pair do
      resolve(fn _ -> {:ok, %{beta: :beta_pair, gamma: :gamma_pair}} end)

      produce :beta
      produce :gamma
    end

    command :make_all_one do
      resolve(fn _ -> {:ok, %{alpha: :alpha_one, beta: :beta_one, gamma: :gamma_one}} end)

      produce :alpha
      produce :beta
      produce :gamma
    end

    command :make_all_two do
      resolve(fn _ -> {:ok, %{alpha: :alpha_two, beta: :beta_two, gamma: :gamma_two}} end)

      produce :alpha
      produce :beta
      produce :gamma
    end

    command :from_beta do
      param :beta, entity: :beta

      resolve(fn _ -> {:ok, %{alpha: :alpha_from_beta, gamma: :gamma_from_beta}} end)

      produce :alpha
      produce :gamma
    end

    command :from_alpha_and_beta do
      param :alpha, entity: :alpha
      param :beta, entity: :beta

      resolve(fn _ -> {:ok, %{gamma: :gamma_from_both}} end)

      produce :gamma
    end
  end

  use SeedFactory.Test, schema: Schema

  test "head-order resolution keeps a command for every demanded entity", context do
    context = produce(context, [:alpha, :beta, :gamma])

    assert %{alpha: _, beta: _, gamma: _} = context
  end
end
