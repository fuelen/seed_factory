defmodule SeedFactory.UncertainShelterFallbackTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    command :make_e do
      resolve(fn _ -> {:ok, %{e: :initial}} end)
      produce :e
    end

    command :wipe do
      param :e, entity: :e

      resolve(fn _ ->
        send(self(), {:ran, :wipe})
        {:ok, %{e: :wiped, w: :w}}
      end)

      update :e
      produce :w
    end

    command :maybe_restore do
      param :e, entity: :e
      param :w, entity: :w
      param :mode, generate: fn -> Process.get(:restore_mode, :full) end

      resolve(fn args ->
        send(self(), {:ran, :maybe_restore})
        {:ok, %{e: {:restored, args.mode}, b: :b}}
      end)

      update :e
      produce :b
    end

    command :sure_restore do
      param :e, entity: :e

      resolve(fn _ ->
        send(self(), {:ran, :sure_restore})
        {:ok, %{e: :damaged, z: :z}}
      end)

      update :e
      produce :z
    end

    command :use_e do
      # Check :ready first: placing :sure_restore initially shelters it, but
      # then loses :intact. The search must backtrack to :maybe_restore.
      param :e, entity: :e, with_traits: [:ready, :intact]
      param :b, entity: :b

      resolve(fn args ->
        send(self(), {:ran, :use_e})
        {:ok, %{result: args.e}}
      end)

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
      exec :maybe_restore, args_pattern: %{mode: :full}
    end

    trait :ready, :e do
      exec :sure_restore
    end

    trait :damaged, :e do
      from :intact
      exec :sure_restore
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a possible shelter remains a fallback when the certain one loses another required trait",
       context do
    initial = exec(context, :make_e)

    for request <- [[:result, :z], [:z, :result]] do
      assert %{result: {:restored, :full}, e: :damaged, z: :z} = produce(initial, request)
      assert_received {:ran, :wipe}
      assert_received {:ran, :maybe_restore}
      assert_received {:ran, :use_e}
      assert_received {:ran, :sure_restore}
    end
  end

  test "an unsuccessful fallback is refused before any resolver runs", context do
    Process.put(:restore_mode, :partial)
    initial = exec(context, :make_e)

    assert_raise SeedFactory.MissingRequestedTraitError, fn ->
      produce(initial, [:result, :z])
    end

    refute_received {:ran, _}
  end
end
