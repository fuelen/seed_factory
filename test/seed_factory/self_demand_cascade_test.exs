defmodule SeedFactory.SelfDemandCascadeTest do
  use ExUnit.Case, async: true

  import TraitAssertions

  defmodule Schema do
    use SeedFactory.Schema

    # :refine_beta demands its own trait exec, so its requires set gains a
    # self-edge when the trait registers both declarations as candidates. The
    # removal cascade must survive meeting the node it is removing.
    command :make_one do
      resolve(fn _ -> {:ok, %{alpha: :alpha_one, beta: :beta_one}} end)

      produce :alpha
      produce :beta
    end

    command :make_two do
      resolve(fn _ -> {:ok, %{alpha: :alpha_two, beta: :beta_two}} end)

      produce :alpha
      produce :beta
    end

    command :refine_beta do
      param :beta, entity: :beta, with_traits: [:refined]

      resolve(fn _ -> {:ok, %{beta: :beta_refined}} end)

      update :beta
    end

    trait :refined, :beta do
      exec :make_two
    end

    trait :refined, :beta do
      exec :refine_beta
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a command demanding its own trait exec does not crash the planner", context do
    context = produce(context, [:alpha, beta: [:refined]])

    assert_trait(context, :beta, [:refined])
    assert Map.has_key?(context, :alpha)
  end
end
