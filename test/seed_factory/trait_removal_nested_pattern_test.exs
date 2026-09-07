defmodule SeedFactory.TraitRemovalNestedPatternTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Nested args_patterns over a container param, a nil param and a generate
    # param. Two chosen declarations of :tune_e merge their patterns into one
    # argument map, and the transitions from the requested :t1 are judged
    # against that map key by key.
    command :make_e do
      resolve(fn _ -> {:ok, %{e: :e1}} end)

      produce :e
    end

    command :tune_e do
      param :e, entity: :e

      param :opts do
        param :depth, value: 1
        param :color, value: :red
      end

      param :extra, value: nil
      param :note, value: nil

      resolve(fn _ -> {:ok, %{e: :e2}} end)

      update :e
    end

    command :wipe_e do
      param :e, entity: :e
      param :note, value: nil

      resolve(fn _ -> {:ok, %{e: :e4}} end)

      update :e
    end

    command :regen_e do
      param :e, entity: :e
      param :gen, generate: fn -> %{level: 1} end

      resolve(fn _ -> {:ok, %{e: :e5}} end)

      update :e
    end

    command :probe_e do
      param :e, entity: :e
      param :gen, generate: fn -> %{level: 1} end

      resolve(fn _ -> {:ok, %{e: :e3}} end)

      update :e
    end

    trait :t1, :e do
      exec :make_e
    end

    trait :tn, :e do
      exec :tune_e, args_pattern: %{opts: %{depth: 2}, extra: :x}
    end

    trait :tm, :e do
      exec :tune_e, args_pattern: %{opts: %{color: :blue}, extra: :x}
    end

    # Contradicted by the merged depth 2 and color :blue respectively.
    trait :t9, :e do
      from :t1
      exec :tune_e, args_pattern: %{opts: %{depth: 1}}
    end

    trait :t6, :e do
      from :t1
      exec :tune_e, args_pattern: %{opts: %{color: :red}}
    end

    # A nested pattern over a nil param never matches, as nil[:a] is nil.
    trait :t8, :e do
      from :t1
      exec :tune_e, args_pattern: %{note: %{a: 1}}
    end

    # A re-add under a nested pattern over a nil param never fires: the loss
    # is certain, already in the search.
    trait :tw, :e do
      exec :wipe_e
    end

    trait :t5, :e do
      from :t1
      exec :wipe_e
    end

    trait :t1, :e do
      exec :wipe_e, args_pattern: %{note: %{a: 1}}
    end

    # A re-add under a nested pattern over a generated value: unknown in the
    # search, known in the prediction.
    trait :tr, :e do
      exec :regen_e
    end

    trait :t4, :e do
      from :t1
      exec :regen_e
    end

    trait :t1, :e do
      exec :regen_e, args_pattern: %{gen: %{level: 1}}
    end

    trait :tp, :e do
      exec :probe_e
    end

    # A nested pattern over a generated value: the search cannot tell, the
    # prediction on the fixed args can.
    trait :t7, :e do
      from :t1
      exec :probe_e, args_pattern: %{gen: %{level: 1}}
    end
  end

  use SeedFactory.Test, schema: Schema

  import TraitAssertions

  test "nested patterns are judged against the merged args of the chosen declarations", context do
    context = exec(context, :make_e)
    context = produce(context, e: [:t1, :tn, :tm])

    assert_trait(context, :e, [:t1, :tn, :tm])
  end

  test "a re-add under a nested pattern over a nil param is a certain loss", context do
    context = exec(context, :make_e)

    assert_raise SeedFactory.TraitResolutionError,
                 "cannot satisfy trait :t1 for entity :e (requested trait)\n" <>
                   "- command :wipe_e, chosen for the plan, applies :t5 and removes :t1",
                 fn ->
                   produce(context, e: [:t1, :tw])
                 end
  end

  test "a re-add under a nested pattern over a generated value is judged on the fixed args",
       context do
    context = exec(context, :make_e)
    context = produce(context, e: [:t1, :tr])

    current = context.__seed_factory_meta__.current_traits.e
    assert :t1 in current
    assert :tr in current
  end

  test "a transition under a nested pattern over a generated value is judged on the fixed args",
       context do
    context = exec(context, :make_e)

    assert_raise SeedFactory.MissingRequestedTraitError,
                 "requested trait :t1 would be missing on :e after the plan: " <>
                   "command :probe_e removes it",
                 fn ->
                   produce(context, e: [:t1, :tp])
                 end
  end
end
