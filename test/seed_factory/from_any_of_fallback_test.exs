defmodule SeedFactory.FromAnyOfFallbackTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :final accepts either :path_a or :path_b. When the :path_a route is dead
    # because its command already ran without matching the args pattern, the
    # planner must fall back to :path_b.
    command :create_item do
      resolve(fn _ -> {:ok, %{item: :new_item}} end)

      produce :item
    end

    command :process_a do
      param :item, entity: :item
      param :mode, value: :a

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

    trait :new, :item do
      exec :create_item
    end

    trait :path_a, :item do
      from :new
      exec :process_a, args_pattern: %{mode: :a}
    end

    trait :path_b, :item do
      from :new
      exec :process_b
    end

    trait :final, :item do
      from [:path_a, :path_b]
      exec :finish
    end
  end

  use SeedFactory.Test, schema: Schema
  import TraitAssertions

  test "falls back to the second from option when the first is dead", context do
    context =
      context
      |> produce(:item)
      |> exec(:process_a, mode: :x)
      |> produce(item: [:final])

    assert context.item == :item_final
    assert_trait(context, :item, [:final])
  end

  test "the first from option is used on a fresh entity", context do
    context = produce(context, item: [:final])

    assert context.item == :item_final
    assert_trait(context, :item, [:final])
  end
end
