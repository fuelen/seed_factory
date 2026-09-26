defmodule SeedFactory.TraitFromRemovesEveryOccurrenceTest do
  use ExUnit.Case, async: true
  import SeedFactory

  defmodule Schema do
    use SeedFactory.Schema

    command :create do
      resolve(fn _ -> {:ok, %{item: :item}} end)

      produce :item
    end

    command :touch do
      param :item, entity: :item

      resolve(fn args -> {:ok, %{item: args.item}} end)

      update :item
    end

    command :archive do
      param :item, entity: :item

      resolve(fn args -> {:ok, %{item: args.item}} end)

      update :item
    end

    trait :fresh, :item do
      exec :create
    end

    trait :fresh, :item do
      exec :touch
    end

    trait :archived, :item do
      from :fresh
      exec :archive
    end
  end

  test "a transition removes every occurrence of the trait it leaves" do
    ctx = init(%{}, Schema) |> exec(:create) |> exec(:touch)
    assert ctx.__seed_factory_meta__.current_traits.item == [:fresh, :fresh]

    ctx = exec(ctx, :archive)
    assert ctx.__seed_factory_meta__.current_traits.item == [:archived]
  end
end
