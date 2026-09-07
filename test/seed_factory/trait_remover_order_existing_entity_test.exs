defmodule SeedFactory.TraitRemoverOrderExistingEntityTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Pre-existing hole (v0.8.2 failed identically) and the
    # worst of its three forms: with_traits is a planning-only filter, so when
    # the trait remover of an existing entity ran before the consumer, the
    # consumer SILENTLY got the entity in the wrong state.
    command :create_a do
      resolve(fn _ -> {:ok, %{a: :a1}} end)

      produce :a
    end

    command :promote_a do
      param :a, entity: :a

      resolve(fn _ -> {:ok, %{a: :a_promoted, p: :p1}} end)

      update :a
      produce :p
    end

    command :use_fresh_a do
      param :a, entity: :a, with_traits: [:fresh]

      resolve(fn args -> {:ok, %{q: args.a}} end)

      produce :q
    end

    trait :fresh, :a do
      exec :create_a
    end

    trait :promoted, :a do
      from :fresh
      exec :promote_a
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a consumer of an existing entity runs before the trait remover", context do
    context = context |> produce(:a) |> produce([:p, :q])

    # use_fresh_a must see :a while it still has the :fresh trait
    assert context.q == :a1
  end
end
