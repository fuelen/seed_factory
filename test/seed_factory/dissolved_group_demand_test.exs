defmodule SeedFactory.DissolvedGroupDemandTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Declaration order matters. The demand for :delta resolves the :alpha
    # group in favour of :combo_one, which removes :combo_two and dissolves the
    # :beta group down to :combo_three. The :gamma group [:make_gamma,
    # :combo_three] must then list :make_gamma first, so its head-order
    # resolution is what removes the surviving producer of :beta.
    command :combo_one do
      resolve(fn _ -> {:ok, %{alpha: :alpha_one, delta: :delta_one}} end)

      produce :alpha
      produce :delta
    end

    command :combo_two do
      resolve(fn _ -> {:ok, %{alpha: :alpha_two, beta: :beta_two}} end)

      produce :alpha
      produce :beta
    end

    command :make_gamma do
      resolve(fn _ -> {:ok, %{gamma: :gamma_solo}} end)

      produce :gamma
    end

    command :combo_three do
      resolve(fn _ -> {:ok, %{beta: :beta_three, gamma: :gamma_three}} end)

      produce :beta
      produce :gamma
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a demand survives the dissolution of its conflict group", context do
    # :delta goes last: its single-candidate demand triggers the resolution
    # only after all three groups are built.
    context = produce(context, [:alpha, :beta, :gamma, :delta])

    assert %{alpha: _, beta: _, gamma: _, delta: _} = context
  end
end
