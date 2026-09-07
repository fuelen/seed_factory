defmodule SeedFactory.DeferredReAddTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :wipe_e removes :t1 for sure (a pattern over its
    # generate param, fixed before the execution) and :restore_e re-declares
    # :t1 under a condition reading the instance :wipe_e updates. The plan
    # cannot refuse before :wipe_e, as the re-add may still fire; :wipe_e runs,
    # the re-add turns out not to fire, and the refusal comes before
    # :restore_e, naming the executed remover.
    command :make_e do
      resolve(fn _ -> {:ok, %{e: %{fresh: true}}} end)

      produce :e
    end

    command :wipe_e do
      param :e, entity: :e
      param :g, generate: fn -> :on end

      resolve(fn _ -> {:ok, %{e: %{fresh: false}, w: :w1}} end)

      update :e
      produce :w
    end

    command :restore_e do
      param :e, entity: :e
      param :w, entity: :w

      resolve(fn _ -> {:ok, %{e: %{fresh: false}, v: :v1}} end)

      update :e
      produce :v
    end

    trait :t1, :e do
      exec :make_e
    end

    trait :t9, :e do
      from :t1
      exec :wipe_e, args_pattern: %{g: :on}
    end

    trait :t1, :e do
      exec :restore_e,
        args_match: fn args -> args.e.fresh end,
        generate_args: fn -> %{} end
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a removal followed by an uncertain re-add is refused before the re-adding command",
       context do
    context = exec(context, :make_e)

    error =
      assert_raise SeedFactory.MissingRequestedTraitError,
                   "requested trait :t1 would be missing on :e after the plan: " <>
                     "command :wipe_e removed it and no later planned command applies it",
                   fn ->
                     produce(context, e: [:t1], v: [])
                   end

    assert error.removed_by == :wipe_e
    assert error.removed_when == :executed
  end

  test "the remover has already run when the plan is refused", context do
    context = exec(context, :make_e)
    context = exec(context, :wipe_e)

    refute :t1 in context.__seed_factory_meta__.current_traits.e
  end
end
