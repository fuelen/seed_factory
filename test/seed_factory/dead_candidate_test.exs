defmodule SeedFactory.DeadCandidateTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # The demand of :consume_zeta narrows the grown group [:make_pair,
    # :make_pair_dep, :make_extra] to [:make_pair, :make_extra]. Removing the
    # diff member :make_pair_dep cascades through :make_yield into
    # :make_extra, a member of the demand's own candidate list, so only the
    # surviving candidate can be linked.
    command :make_pair do
      resolve(fn _ -> {:ok, %{dep_pair: :a_pair, grown: :a_grown, zeta: :a_zeta}} end)

      produce :dep_pair
      produce :grown
      produce :zeta
    end

    command :make_pair_dep do
      param :yield, entity: :yield

      resolve(fn _ -> {:ok, %{dep_pair: :d_pair, grown: :d_grown}} end)

      produce :dep_pair
      produce :grown
    end

    command :consume_zeta do
      param :zeta, entity: :zeta

      resolve(fn _ -> {:ok, %{wide: :wide}} end)

      produce :wide
    end

    command :make_yield do
      param :grown, entity: :grown

      resolve(fn _ -> {:ok, %{yield: :yield}} end)

      produce :yield
    end

    command :make_extra do
      resolve(fn _ -> {:ok, %{grown: :m_grown, zeta: :m_zeta}} end)

      produce :grown
      produce :zeta
    end

    command :make_root do
      param :dep_pair, entity: :dep_pair
      param :wide, entity: :wide

      resolve(fn _ -> {:ok, %{root: :root}} end)

      produce :root
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a demand links only the candidates that survived the diff cascade", context do
    context = produce(context, [:root])

    assert Map.has_key?(context, :root)
  end
end
