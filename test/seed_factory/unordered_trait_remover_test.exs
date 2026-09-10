defmodule SeedFactory.UnorderedTraitRemoverTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    command :make_e do
      resolve(fn _ -> {:ok, %{e: :initial}} end)

      produce :e
    end

    command :use_ready do
      param :e, entity: :e, with_traits: [:ready]

      resolve(fn args ->
        send(self(), {:ran, :use_ready})
        {:ok, %{e: :used_ready, a: args.e}}
      end)

      update :e
      produce :a
    end

    command :use_intact do
      param :e, entity: :e, with_traits: [:intact]

      resolve(fn args ->
        send(self(), {:ran, :use_intact})
        {:ok, %{e: :used_intact, b: args.e}}
      end)

      update :e
      produce :b
    end

    command :restore_ready do
      param :e, entity: :e

      resolve(fn _ ->
        send(self(), {:ran, :restore_ready})
        {:ok, %{e: :restored, r: :r}}
      end)

      update :e
      produce :r
    end

    trait :ready, :e do
      exec :make_e
    end

    trait :intact, :e do
      exec :make_e
    end

    trait :lost_intact, :e do
      from :intact
      exec :use_ready
    end

    trait :lost_ready, :e do
      from :ready
      exec :use_intact
    end

    trait :ready, :e do
      exec :restore_ready
    end
  end

  use SeedFactory.Test, schema: Schema

  test "an unordered remover can precede the consumer when a later command restores its trait",
       context do
    initial = exec(context, :make_e)

    manual =
      initial
      |> exec(:use_intact)
      |> exec(:restore_ready)
      |> exec(:use_ready)

    assert %{a: :restored, b: :initial, r: :r} = manual

    for request <- [
          [:a, :b, :r],
          [:a, :r, :b],
          [:b, :a, :r],
          [:b, :r, :a],
          [:r, :a, :b],
          [:r, :b, :a]
        ] do
      assert %{a: :restored, b: :initial, r: :r} = produce(initial, request)
    end
  end

  test "opposing consumers without a restoring command fail before either runs", context do
    initial = exec(context, :make_e)

    for request <- [[:a, :b], [:b, :a]] do
      assert_raise SeedFactory.TraitResolutionError, fn -> produce(initial, request) end
    end

    refute_received {:ran, _}
  end
end
