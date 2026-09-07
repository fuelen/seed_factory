defmodule SeedFactory.ReproducerTraitConsumerTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Trait-flavored variant of reproducer_consumer_order:
    # the consumer depends on the re-producer through a creation trait instead
    # of a second entity. Valid order: del_a -> remake_a -> use_t.
    command :create_a do
      resolve(fn _ -> {:ok, %{a: :a1}} end)

      produce :a
    end

    command :del_a do
      param :a, entity: :a

      resolve(fn _ -> {:ok, %{x: :x1}} end)

      produce :x
      delete :a
    end

    command :remake_a do
      resolve(fn _ -> {:ok, %{a: :a2}} end)

      produce :a
    end

    command :use_t do
      param :a, entity: :a, with_traits: [:fresh]

      resolve(fn args -> {:ok, %{q: args.a}} end)

      produce :q
    end

    trait :fresh, :a do
      exec :remake_a
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a trait consumer fed by the re-producer does not trap the deleter", context do
    context = context |> produce(:a) |> produce([:x, :q])

    assert Map.has_key?(context, :x)
    assert context.q == :a2
    assert context.a == :a2
  end
end
