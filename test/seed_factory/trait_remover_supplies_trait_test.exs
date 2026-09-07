defmodule SeedFactory.TraitRemoverSuppliesTraitTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Minimized from from_any stress seed 313. :promote_a both supplies :ready
    # (its exec) and potentially removes it (:done transitions from :ready),
    # so the "consumers run before trait removers" ordering must not fire
    # against a consumer whose :ready comes from :promote_a itself - the plan
    # already orders them the other way. The unguarded link made this plan
    # raise CircularDependencyError.
    command :make_a do
      resolve(fn _ -> {:ok, %{a: :a1}} end)

      produce :a
    end

    command :promote_a do
      param :a, entity: :a

      resolve(fn _ -> {:ok, %{a: :a_ready}} end)

      update :a
    end

    command :use_ready_a do
      param :a, entity: :a, with_traits: [:ready]

      resolve(fn args -> {:ok, %{q: args.a}} end)

      produce :q
    end

    trait :ready, :a do
      exec :promote_a
    end

    trait :done, :a do
      from :ready
      exec :promote_a
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a consumer fed by the trait remover itself runs after it", context do
    context = produce(context, :q)

    assert context.q == :a_ready
  end
end
