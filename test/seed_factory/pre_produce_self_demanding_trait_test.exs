defmodule SeedFactory.PreProduceSelfDemandingTraitTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Minimized from mixed stress seeds 314/351. :seal_dep is the only exec of
    # :sealed and demands a :dep that already has :sealed, so the trait cannot
    # be bootstrapped by any plan. v0.8.2 pre_produce returned a hollow :ok
    # (nothing was prepared for the trait and a later produce raised anyway);
    # refusing loudly at planning is the honest answer.
    command :make_dep do
      resolve(fn _ -> {:ok, %{dep: :dep}} end)

      produce :dep
    end

    command :seal_dep do
      param :dep, entity: :dep, with_traits: [:sealed]

      resolve(fn _ -> {:ok, %{dep: :sealed_dep}} end)

      update :dep
    end

    trait :sealed, :dep do
      exec :seal_dep
    end
  end

  use SeedFactory.Test, schema: Schema

  test "an unbootstrappable trait chain fails loudly in pre_produce too", context do
    context = exec(context, :make_dep)

    assert_raise SeedFactory.TraitResolutionError, fn ->
      pre_produce(context, dep: [:sealed])
    end

    assert_raise SeedFactory.TraitResolutionError,
                 "cannot satisfy trait :sealed for entity :dep (trait required by :seal_dep command)\n" <>
                   "- candidate command :seal_dep demands the trait it provides",
                 fn ->
                   produce(context, dep: [:sealed])
                 end
  end
end
