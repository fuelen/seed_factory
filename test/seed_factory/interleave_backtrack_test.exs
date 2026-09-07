defmodule SeedFactory.InterleaveBacktrackTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Both producers make both shared entities, and each shared entity has its
    # own deleter. The only valid order is make_beta -> both burns ->
    # make_alpha, but for :first_shared alone the reverse order is consistent
    # too: whichever sequence is tried first for it, only :second_shared can
    # tell whether it fits, so the leaf ordering must backtrack across
    # entities instead of committing per entity.
    command :make_alpha do
      resolve(fn _ -> {:ok, %{alpha: :alpha, first_shared: :fs_a, second_shared: :ss_a}} end)

      produce :alpha
      produce :first_shared
      produce :second_shared
    end

    command :make_beta do
      resolve(fn _ ->
        {:ok, %{beta: :beta, first_shared: :fs_b, second_shared: :ss_b, fuel: :fuel}}
      end)

      produce :beta
      produce :first_shared
      produce :second_shared
      produce :fuel
    end

    command :burn_first do
      resolve(fn _ -> {:ok, %{ash_one: :ash_one}} end)

      produce :ash_one
      delete :first_shared
    end

    command :burn_second do
      param :fuel, entity: :fuel

      resolve(fn _ -> {:ok, %{ash_two: :ash_two}} end)

      produce :ash_two
      delete :second_shared
    end
  end

  use SeedFactory.Test, schema: Schema

  test "the interleave order of one entity backtracks for the sake of another", context do
    context = produce(context, [:alpha, :beta, :ash_one, :ash_two])

    assert Map.has_key?(context, :alpha)
    assert Map.has_key?(context, :beta)
    assert Map.has_key?(context, :ash_one)
    assert Map.has_key?(context, :ash_two)
  end
end
