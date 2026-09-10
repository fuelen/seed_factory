defmodule SeedFactory.UncertainShelterTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :wipe strips :ready from the e in the context and :restore, planned
    # after it for r, applies :ready again only when its generated :mode is
    # :full. The search cannot know the value, so it orders :restore between
    # the loss and :use_e and leaves the verdict to the prediction, which
    # reads the generated value before anything runs.
    command :make_e do
      resolve(fn _ -> {:ok, %{e: :fresh}} end)

      produce :e
    end

    command :wipe do
      param :e, entity: :e

      resolve(fn _ ->
        send(self(), {:ran, :wipe})
        {:ok, %{e: :wiped, w: :w1}}
      end)

      update :e
      produce :w
    end

    command :restore do
      param :e, entity: :e
      param :w, entity: :w
      param :mode, generate: fn -> Process.get(:restore_mode, :full) end

      resolve(fn args -> {:ok, %{e: {:restored, args.mode}, r: :r1}} end)

      update :e
      produce :r
    end

    command :use_e do
      param :e, entity: :e, with_traits: [:ready]
      param :r, entity: :r

      resolve(fn args ->
        send(self(), {:ran, :use_e})
        {:ok, %{result: args.e}}
      end)

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
      exec :restore, args_pattern: %{mode: :full}
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a re-applier the search cannot judge shelters the consumer when its args fit", context do
    context = context |> exec(:make_e) |> produce(:result)

    assert context.result == {:restored, :full}
    assert :ready in context.__seed_factory_meta__.current_traits.e
  end

  test "when the generated args do not fit, the loss is refused before anything runs", context do
    Process.put(:restore_mode, :partial)
    context = exec(context, :make_e)

    assert_raise SeedFactory.MissingRequestedTraitError,
                 "trait :ready required by :use_e would be missing on :e when it runs: " <>
                   "command :wipe removes it",
                 fn -> produce(context, :result) end

    refute_received {:ran, _}
  end
end
