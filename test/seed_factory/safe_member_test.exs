defmodule SeedFactory.SafeMemberTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # At resolution time no group HEAD is safe: every head's cascade wipes out
    # all commands of some demanded group. The safe choice is :make_all, a
    # non-head member, so the sweep past the heads has to find it.
    command :make_alpha_gamma do
      resolve(fn _ -> {:ok, %{alpha: :alpha_ag, gamma: :gamma_ag}} end)

      produce :alpha
      produce :gamma
    end

    command :make_alpha_beta_one do
      resolve(fn _ -> {:ok, %{alpha: :alpha_one, beta: :beta_one}} end)

      produce :alpha
      produce :beta
    end

    command :make_all do
      resolve(fn _ -> {:ok, %{alpha: :alpha_all, beta: :beta_all, gamma: :gamma_all}} end)

      produce :alpha
      produce :beta
      produce :gamma
    end

    command :make_alpha_beta_two do
      param :gamma, entity: :gamma

      resolve(fn _ -> {:ok, %{alpha: :alpha_two, beta: :beta_two}} end)

      produce :alpha
      produce :beta
    end
  end

  use SeedFactory.Test, schema: Schema

  test "resolution falls back to a safe non-head member", context do
    context = produce(context, [:beta])

    assert %{beta: _} = context
  end
end
