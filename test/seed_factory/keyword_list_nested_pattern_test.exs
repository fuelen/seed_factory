defmodule SeedFactory.KeywordListNestedPatternTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # A nested args_pattern over a param whose value is
    # a keyword list: `Trait.deep_equal_maps?` reads `map2[key]` through
    # Access, which works on a keyword list, so both declarations fire at
    # runtime. The prediction has to read the value the same way.
    command :make_e do
      resolve(fn _ -> {:ok, %{e: :e1}} end)

      produce :e
    end

    command :wipe_e do
      param :e, entity: :e
      param :opts, value: [a: 1]

      resolve(fn _ -> {:ok, %{e: :e2, w: :w1}} end)

      update :e
      produce :w
    end

    command :stamp_e do
      param :e, entity: :e
      param :opts, value: [a: 1]

      resolve(fn _ -> {:ok, %{e: :e3, x: :x1}} end)

      update :e
      produce :x
    end

    trait :t1, :e do
      exec :make_e
    end

    trait :t9, :e do
      from :t1
      exec :wipe_e, args_pattern: %{opts: %{a: 1}}
    end

    trait :t8, :e do
      from :t1
      exec :stamp_e
    end

    trait :t1, :e do
      exec :stamp_e, args_pattern: %{opts: %{a: 1}}
    end

    # Requesting :x with :tx keeps the :t1 re-add off the edge, so it is
    # judged against the literal default [a: 1].
    trait :tx, :x do
      exec :stamp_e
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a transition firing over a keyword-list value is a remover", context do
    context = exec(context, :make_e)

    # Was: a context whose :e silently lacked the requested :t1.
    assert_raise SeedFactory.TraitResolutionError,
                 "cannot satisfy trait :t1 for entity :e (requested trait)\n" <>
                   "- command :wipe_e, chosen for the plan, applies :t9 and removes :t1",
                 fn ->
                   produce(context, e: [:t1], w: [])
                 end
  end

  test "a re-add firing over a keyword-list value saves the plan", context do
    context = exec(context, :make_e)
    context = produce(context, e: [:t1], x: [:tx])

    current = context.__seed_factory_meta__.current_traits.e
    assert :t1 in current
    assert :t8 in current
  end
end
