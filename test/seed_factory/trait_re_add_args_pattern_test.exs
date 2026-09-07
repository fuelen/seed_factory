defmodule SeedFactory.TraitReAddArgsPatternTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :touch_e re-declares :t1 under args_pattern
    # %{mode: :a} and transitions :t9 from :t1 under %{mode: :b}. Chosen for
    # :tw alone it runs with the default :b: the transition fires, the re-add
    # does not, and the entity loses the requested :t1. Chosen for :ta it runs
    # with :a from that declaration's pattern, and then the transition cannot
    # fire.
    command :make_e do
      resolve(fn _ -> {:ok, %{e: :e1}} end)

      produce :e
    end

    command :touch_e do
      param :e, entity: :e
      param :mode, value: :b

      resolve(fn _ -> {:ok, %{e: :e2, w: :w1}} end)

      update :e
      produce :w
    end

    trait :t1, :e do
      exec :make_e
    end

    trait :t1, :e do
      exec :touch_e, args_pattern: %{mode: :a}
    end

    trait :t9, :e do
      from :t1
      exec :touch_e, args_pattern: %{mode: :b}
    end

    trait :ta, :e do
      exec :touch_e, args_pattern: %{mode: :a}
    end

    trait :tw, :w do
      exec :touch_e
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a re-add whose pattern the literal args contradict does not save the plan", context do
    context = exec(context, :make_e)

    # Was: a context whose :e silently lacked the requested :t1.
    assert_raise SeedFactory.TraitResolutionError,
                 "cannot satisfy trait :t1 for entity :e (requested trait)\n" <>
                   "- command :touch_e, chosen for the plan, applies :t9 and removes :t1",
                 fn ->
                   produce(context, e: [:t1], w: [:tw])
                 end
  end

  test "the pattern of a chosen declaration fixes the args the plan is judged by", context do
    context = exec(context, :make_e)
    context = produce(context, e: [:t1, :ta])

    current = context.__seed_factory_meta__.current_traits.e
    assert :t1 in current
    assert :ta in current
    refute :t9 in current
  end
end
