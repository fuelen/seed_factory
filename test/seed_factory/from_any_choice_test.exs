defmodule SeedFactory.FromAnyChoiceTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :final is declared twice, so picking the declaration with the from list
    # is a real decision whose lookahead sees the pending from options.
    command :create_item do
      resolve(fn _ -> {:ok, %{item: :new_item}} end)

      produce :item
    end

    command :process_a do
      param :item, entity: :item

      resolve(fn _ -> {:ok, %{item: :item_a}} end)

      update :item
    end

    command :process_b do
      param :item, entity: :item

      resolve(fn _ -> {:ok, %{item: :item_b}} end)

      update :item
    end

    command :finish do
      param :item, entity: :item

      resolve(fn _ -> {:ok, %{item: :item_final}} end)

      update :item
    end

    command :finish_alt do
      param :item, entity: :item

      resolve(fn _ -> {:ok, %{item: :item_final_alt}} end)

      update :item
    end

    trait :path_a, :item do
      exec :process_a
    end

    trait :path_b, :item do
      exec :process_b
    end

    trait :final, :item do
      from [:path_a, :path_b]
      exec :finish
    end

    trait :final, :item do
      exec :finish_alt
    end
  end

  use SeedFactory.Test, schema: Schema
  import TraitAssertions

  test "the first declaration wins and takes the first from option", context do
    context = produce(context, item: [:final])

    assert context.item == :item_final
    assert_trait(context, :item, [:final])
  end
end
