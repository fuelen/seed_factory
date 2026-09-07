defmodule SeedFactory.DeleterPlanChoiceTraitTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Minimized from rich-seq stress seed 548. :make_beta_gamma with
    # :make_alpha satisfies the request. The resolution takes :make_gamma for
    # the tagged :gamma first, which excludes :make_beta_gamma, so :beta falls
    # to the deleter and the requested :gamma is consumed on the way. v0.8.2
    # planned make_beta_gamma -> make_alpha.
    command :make_gamma do
      resolve(fn _ -> {:ok, %{gamma: {:g, :gamma}}} end)

      produce :gamma
    end

    command :make_beta_gamma do
      resolve(fn _ -> {:ok, %{beta: {:bg, :beta}, gamma: {:bg, :gamma}}} end)

      produce :beta
      produce :gamma
    end

    command :make_alpha do
      resolve(fn _ -> {:ok, %{alpha: {:a, :alpha}}} end)

      produce :alpha
    end

    command :make_beta_from_gamma do
      param :gamma, entity: :gamma

      resolve(fn _ -> {:ok, %{beta: {:bfg, :beta}}} end)

      produce :beta
      delete :gamma
    end

    trait :tagged, :gamma do
      exec :make_gamma
    end

    trait :tagged, :gamma do
      exec :make_beta_gamma
    end
  end

  use SeedFactory.Test, schema: Schema
  import TraitAssertions

  test "a plan without the deleter is preferred for a requested trait too", context do
    context = produce(context, [:alpha, :beta, {:gamma, [:tagged]}])

    assert Map.has_key?(context, :alpha)
    assert Map.has_key?(context, :beta)
    assert_trait(context, :gamma, [:tagged])
  end
end
