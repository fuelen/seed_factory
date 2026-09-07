defmodule SeedFactory.TraitReAddGeneratedArgsTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # The opaque side of the protection. Whether a declaration fires can
    # depend on values the plan does not know: an args_match function, the
    # args a chosen args_match declaration generates, a generate param. The
    # search refuses only a certain loss; an uncertain re-add of the requested
    # :t1 is judged once the args are fixed, right before the execution. Every
    # updater transitions away from :t1 unconditionally,
    # re-declares :t1 conditionally, and is chosen for a transition from :t2
    # (so no declaration of :t1 rides its edge).
    command :make_e do
      resolve(fn _ -> {:ok, %{e: :e1}} end)

      produce :e
    end

    command :make_plain_e do
      resolve(fn _ -> {:ok, %{e: :plain_e}} end)

      produce :e
    end

    command :stamp_e do
      param :e, entity: :e
      param :level, value: 1

      resolve(fn _ -> {:ok, %{e: :e2}} end)

      update :e
    end

    command :mint_e do
      param :e, entity: :e
      param :kind, value: :x

      resolve(fn _ -> {:ok, %{e: :e3}} end)

      update :e
    end

    # Produces :v, so a request for :t1 puts its :t1 declaration on the edge
    # that produces :v (trait preference) and the execution merges the
    # declaration's generated args.
    command :forge_e do
      param :e, entity: :e
      param :level, value: 2

      resolve(fn _ -> {:ok, %{e: :e5, v: :v1}} end)

      update :e
      produce :v
    end

    # Its default :off would fire the transition, but the generated :on does
    # not: the search must not trust the default once generated args are in.
    command :spin_e do
      param :e, entity: :e
      param :mode, value: :off

      resolve(fn _ -> {:ok, %{e: :e6}} end)

      update :e
    end

    command :roll_e do
      param :e, entity: :e
      param :g, generate: fn -> :a end

      resolve(fn _ -> {:ok, %{e: :e4}} end)

      update :e
    end

    trait :t1, :e do
      exec :make_e
    end

    trait :t2, :e do
      exec :make_e
    end

    trait :t2, :e do
      exec :make_plain_e
    end

    trait :t1, :e do
      exec :stamp_e,
        args_match: fn args -> args.level == 1 end,
        generate_args: fn -> %{level: 1} end
    end

    trait :t9, :e do
      from :t1
      exec :stamp_e
    end

    trait :t5, :e do
      from :t2
      exec :stamp_e
    end

    trait :t7, :e do
      from :t2

      exec :mint_e,
        args_match: fn args -> args.kind == :y end,
        generate_args: fn -> %{kind: :y} end
    end

    trait :t1, :e do
      exec :mint_e, args_pattern: %{kind: :x}
    end

    trait :t8, :e do
      from :t1
      exec :mint_e
    end

    trait :t1, :e do
      exec :forge_e,
        args_match: fn args -> args.level == 1 end,
        generate_args: fn -> %{level: 1} end
    end

    trait :t4, :e do
      from :t1
      exec :forge_e
    end

    trait :spun, :e do
      exec :spin_e,
        args_match: fn args -> args.mode == :on end,
        generate_args: fn -> %{mode: :on} end
    end

    trait :t8b, :e do
      from :t1
      exec :spin_e, args_pattern: %{mode: :off}
    end

    trait :t1, :e do
      exec :roll_e, args_pattern: %{g: :a}
    end

    trait :t6, :e do
      from :t1
      exec :roll_e
    end

    trait :t3, :e do
      from :t2
      exec :roll_e
    end
  end

  use SeedFactory.Test, schema: Schema

  import TraitAssertions

  test "an uncertain args_match re-add is left to the execution", context do
    context = exec(context, :make_e)
    context = produce(context, e: [:t1, :t5])

    current = context.__seed_factory_meta__.current_traits.e
    assert :t1 in current
    assert :t5 in current
  end

  test "a chosen args_match declaration fires for sure", context do
    context = exec(context, :make_plain_e)
    context = produce(context, e: [:t1])

    assert_trait(context, :e, [:t1, :t5, :t9])
  end

  test "an args_match declaration riding the edge of a produced entity fires for sure", context do
    context = exec(context, :make_e)
    context = produce(context, e: [:t1], v: [])

    assert context.v == :v1
    assert :t1 in context.__seed_factory_meta__.current_traits.e
  end

  test "a re-add defeated by generated args is refused before the execution", context do
    context = exec(context, :make_e)

    # Was: the generated kind :y defeated the re-add pattern %{kind: :x} and
    # the context silently lacked :t1.
    assert_raise SeedFactory.MissingRequestedTraitError,
                 "requested trait :t1 would be missing on :e after the plan: " <>
                   "command :mint_e removes it",
                 fn ->
                   produce(context, e: [:t1, :t7])
                 end
  end

  test "generated args of a chosen declaration make the search doubt the defaults", context do
    context = exec(context, :make_e)
    context = produce(context, e: [:t1, :spun])

    current = context.__seed_factory_meta__.current_traits.e
    assert :t1 in current
    assert :spun in current
  end

  test "a re-add pattern over a generate param is left to the execution", context do
    context = exec(context, :make_e)
    context = produce(context, e: [:t1, :t3])

    current = context.__seed_factory_meta__.current_traits.e
    assert :t1 in current
    assert :t3 in current
  end
end
