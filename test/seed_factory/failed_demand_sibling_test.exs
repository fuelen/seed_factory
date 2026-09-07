defmodule SeedFactory.FailedDemandSiblingTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Minimized from rich stress seed 218. Requesting :fresh together with
    # :sealed (its from-descendant) is contradictory and fails the :thing
    # demand at collection. Ordering the two :labeled declarations still walks
    # the whole stack, so the planner must survive meeting the failed sibling
    # demand before reporting it.
    command :make_thing do
      resolve(fn _ -> {:ok, %{thing: :thing}} end)

      produce :thing
    end

    command :seal_thing do
      param :thing, entity: :thing

      resolve(fn _ -> {:ok, %{thing: :sealed_thing}} end)

      update :thing
    end

    command :make_other do
      resolve(fn _ -> {:ok, %{other: :other}} end)

      produce :other
    end

    command :make_other_alt do
      resolve(fn _ -> {:ok, %{other: :other_alt}} end)

      produce :other
    end

    trait :fresh, :thing do
      exec :make_thing
    end

    trait :sealed, :thing do
      from :fresh
      exec :seal_thing
    end

    trait :labeled, :other do
      exec :make_other
    end

    trait :labeled, :other do
      exec :make_other_alt
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a failed demand is reported despite an undecided sibling", context do
    assert_raise SeedFactory.TraitRestrictionConflictError, fn ->
      produce(context, [{:thing, [:fresh, :sealed]}, {:other, [:labeled]}])
    end
  end
end
