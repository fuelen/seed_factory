defmodule SeedFactory.DeadDemanderTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :make_part is demanded only through :make_prime_from_part, a group
    # member that the subset demand of :make_part removes as diff. The removal
    # cascade takes :make_part with it, so the demand must expire instead of
    # linking to the dead demander.
    command :make_pair_one do
      resolve(fn _ -> {:ok, %{prime: :prime_one, resource: :resource_one}} end)

      produce :prime
      produce :resource
    end

    command :make_pair_two do
      resolve(fn _ -> {:ok, %{prime: :prime_two, resource: :resource_two}} end)

      produce :prime
      produce :resource
    end

    command :make_prime_from_part do
      param :part, entity: :part

      resolve(fn _ -> {:ok, %{prime: :prime_from_part}} end)

      produce :prime
    end

    command :make_part do
      param :resource, entity: :resource

      resolve(fn _ -> {:ok, %{part: :part}} end)

      produce :part
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a demand expires when the diff removal cascade kills its demander", context do
    context = produce(context, [:prime])

    assert Map.has_key?(context, :prime)
  end
end
