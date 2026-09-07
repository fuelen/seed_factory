defmodule SeedFactory.ReorderedGroupDemandTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # The requested trait reorders the candidates of :gamma, so its demand
    # arrives as the same SET as the existing exclusion group but in another
    # list order. The demand must still be recorded on the group: the request
    # is unsatisfiable and has to raise instead of silently returning a
    # context without :gamma.
    command :make_beta_gamma_one do
      resolve(fn _ -> {:ok, %{beta: {:one, :beta}, gamma: {:one, :gamma}}} end)

      produce :beta
      produce :gamma
    end

    command :make_alpha_beta do
      resolve(fn _ -> {:ok, %{alpha: {:ab, :alpha}, beta: {:ab, :beta}}} end)

      produce :alpha
      produce :beta
    end

    command :make_beta_gamma_two do
      resolve(fn _ -> {:ok, %{beta: {:two, :beta}, gamma: {:two, :gamma}}} end)

      produce :beta
      produce :gamma
    end

    command :make_alpha_gamma do
      resolve(fn _ -> {:ok, %{alpha: {:ag, :alpha}, gamma: {:ag, :gamma}}} end)

      produce :alpha
      produce :gamma
    end

    trait :tagged, :alpha do
      exec :make_alpha_gamma
    end

    trait :tagged, :alpha do
      exec :make_alpha_beta
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a demand equal to a group as a set is recorded despite the order", context do
    assert_raise SeedFactory.UnproducibleEntityError, fn ->
      produce(context, [{:alpha, [:tagged]}, :beta, :gamma])
    end
  end
end
