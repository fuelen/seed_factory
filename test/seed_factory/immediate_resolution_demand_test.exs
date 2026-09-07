defmodule SeedFactory.ImmediateResolutionDemandTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :prime is produced only by :make_prime, whose immediate resolution kills
    # the combo commands. The demand for :omega resurrects them and their
    # resolution kills :make_prime in return. The request is unsatisfiable
    # (:make_prime and the combos collide over :shared), so produce must raise
    # instead of silently dropping :prime.
    command :make_prime do
      resolve(fn _ -> {:ok, %{prime: :prime, shared: :shared_prime}} end)

      produce :prime
      produce :shared
    end

    command :make_combo_one do
      resolve(fn _ -> {:ok, %{alpha: :alpha_one, shared: :shared_one, omega: :omega_one}} end)

      produce :alpha
      produce :shared
      produce :omega
    end

    command :make_combo_two do
      resolve(fn _ -> {:ok, %{alpha: :alpha_two, shared: :shared_two, omega: :omega_two}} end)

      produce :alpha
      produce :shared
      produce :omega
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a demand consumed by an immediate resolution is not forgotten", context do
    assert_raise SeedFactory.UnproducibleEntityError, fn ->
      produce(context, [:alpha, :prime, :omega])
    end
  end
end
