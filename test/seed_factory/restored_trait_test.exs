defmodule SeedFactory.RestoredTraitTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :wipe strips :ready from the e already in the context, and :restore,
    # planned after it for r, applies :ready again; :use_e, planned after
    # :restore, reads a :ready e. The applier of a trait the consumer needs is
    # whichever planned command surely applies it between the loss and the
    # consumer, not only the one that first applied it.
    command :make_e do
      resolve(fn _ -> {:ok, %{e: :ready_e}} end)

      produce :e
    end

    command :wipe do
      param :e, entity: :e

      resolve(fn _ -> {:ok, %{e: :wiped_e, w: :w1}} end)

      update :e
      produce :w
    end

    command :restore do
      param :e, entity: :e
      param :w, entity: :w

      resolve(fn _ -> {:ok, %{e: :restored_e, r: :r1}} end)

      update :e
      produce :r
    end

    command :use_e do
      param :e, entity: :e, with_traits: [:ready]
      param :r, entity: :r

      resolve(fn args -> {:ok, %{result: args.e}} end)

      produce :result
    end

    trait :ready, :e do
      exec :make_e
    end

    trait :wiped, :e do
      from :ready
      exec :wipe
    end

    trait :ready, :e do
      exec :restore
    end
  end

  use SeedFactory.Test, schema: Schema

  test "another planned command restoring the trait before the consumer shelters it", context do
    context = context |> exec(:make_e) |> produce(:result)

    assert context.result == :restored_e
    assert :ready in context.__seed_factory_meta__.current_traits.e
  end
end
