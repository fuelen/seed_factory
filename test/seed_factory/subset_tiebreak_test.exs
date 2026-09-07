defmodule SeedFactory.SubsetTiebreakTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # The :q narrowing has subset [cmd_m, cmd_m_prime]. Picking cmd_m wipes
    # the sole producers of :ea and :eb demanded by cmd_d2 (pending
    # narrowings), while picking cmd_m_prime satisfies everything.
    command :cmd_m do
      resolve(fn _ -> {:ok, %{q: :q_m, p: :p_m, shared_a: :sa_m, shared_b: :sb_m}} end)

      produce :q
      produce :p
      produce :shared_a
      produce :shared_b
    end

    command :cmd_m_prime do
      resolve(fn _ -> {:ok, %{q: :q_mp, p: :p_mp}} end)

      produce :q
      produce :p
    end

    command :cmd_k do
      resolve(fn _ -> {:ok, %{p: :p_k, k_extra: :ke_k}} end)

      produce :p
      produce :k_extra
    end

    command :cmd_k2 do
      resolve(fn _ -> {:ok, %{k_extra: :ke_k2}} end)

      produce :k_extra
    end

    command :cmd_a do
      resolve(fn _ -> {:ok, %{ea: :ea_a, shared_a: :sa_a}} end)

      produce :ea
      produce :shared_a
    end

    command :cmd_b do
      resolve(fn _ -> {:ok, %{eb: :eb_b, shared_b: :sb_b}} end)

      produce :eb
      produce :shared_b
    end

    command :cmd_d2 do
      param :ea, entity: :ea
      param :eb, entity: :eb

      resolve(fn _ -> {:ok, %{r: :r_d2}} end)

      produce :r
    end

    command :cmd_d2_alt do
      resolve(fn _ -> {:ok, %{r: :r_alt}} end)

      produce :r
    end
  end

  use SeedFactory.Test, schema: Schema

  test "narrowing resolution does not wipe other pending narrowings", context do
    context = produce(context, [:p, :k_extra, :shared_a, :shared_b, :q, :r])

    assert Map.has_key?(context, :q)
    assert Map.has_key?(context, :r)
  end

  test "a demand growing an existing conflict group keeps both demands satisfied", context do
    # With :q first, the demand for :p contains the :q group as a subset, so
    # the group must grow with :cmd_k instead of dropping it. Was: a plan with
    # two commands producing :p and EntityAlreadyExistsError at execution.
    context = produce(context, [:q, :r, :p, :k_extra, :shared_a, :shared_b])

    assert Map.has_key?(context, :q)
    assert Map.has_key?(context, :r)
  end
end
