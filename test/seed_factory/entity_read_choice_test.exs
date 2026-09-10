defmodule SeedFactory.EntityReadChoiceTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # e sits in the context with :ready. :wipe, planned for w, strips it;
    # :drop_e deletes e for the receipt and :remake_e produces a new e with
    # :ready for the marker. :use_e needs w and a :ready e: reading the old
    # instance before the deleter loses, reading the new one after the
    # re-producer works.
    command :make_e do
      resolve(fn _ -> {:ok, %{e: :old}} end)

      produce :e
    end

    command :wipe do
      param :e, entity: :e

      resolve(fn _ -> {:ok, %{e: :wiped, w: :w1}} end)

      update :e
      produce :w
    end

    command :drop_e do
      param :e, entity: :e

      resolve(fn _ -> {:ok, %{receipt: :receipt1}} end)

      delete :e
      produce :receipt
    end

    command :remake_e do
      param :receipt, entity: :receipt

      resolve(fn _ -> {:ok, %{e: :new, marker: :marker1}} end)

      produce :e
      produce :marker
    end

    command :use_e do
      param :e, entity: :e, with_traits: [:ready]
      param :w, entity: :w

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
      exec :remake_e
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a reader moves after the re-producer when the old instance cannot serve it", context do
    context = context |> exec(:make_e) |> produce([:result, :marker])

    assert context.result == :new
    assert context.marker == :marker1
  end
end
