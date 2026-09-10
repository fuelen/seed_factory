defmodule SeedFactory.ShelterAlternativeTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # e sits in the context with :ready and :intact. :wipe strips :ready and
    # :use_e needs both traits after it. Both restoring commands are planned
    # for their own outputs and both re-apply :ready, but :restore_first also
    # strips :intact, so only :restore_second can shelter :use_e, whichever
    # the request names first.
    command :make_e do
      resolve(fn _ -> {:ok, %{e: :initial}} end)

      produce :e
    end

    command :wipe do
      param :e, entity: :e

      resolve(fn _ -> {:ok, %{e: :wiped, w: :w1}} end)

      update :e
      produce :w
    end

    command :restore_first do
      param :e, entity: :e

      resolve(fn _ -> {:ok, %{e: :first, first: :first1}} end)

      update :e
      produce :first
    end

    command :restore_second do
      param :e, entity: :e

      resolve(fn _ -> {:ok, %{e: :second, second: :second1}} end)

      update :e
      produce :second
    end

    command :use_e do
      param :e, entity: :e, with_traits: [:ready, :intact]
      param :w, entity: :w

      resolve(fn args -> {:ok, %{result: args.e}} end)

      produce :result
    end

    trait :ready, :e do
      exec :make_e
    end

    trait :intact, :e do
      exec :make_e
    end

    trait :wiped, :e do
      from :ready
      exec :wipe
    end

    trait :ready, :e do
      exec :restore_first
    end

    trait :damaged, :e do
      from :intact
      exec :restore_first
    end

    trait :ready, :e do
      exec :restore_second
    end
  end

  use SeedFactory.Test, schema: Schema

  test "the search moves on to a shelter that keeps the other required trait", context do
    context = exec(context, :make_e)

    for request <- [[:result, :first, :second], [:result, :second, :first]] do
      planned = produce(context, request)

      assert planned.result == :second
      assert planned.first == :first1
      assert planned.second == :second1
    end
  end
end
