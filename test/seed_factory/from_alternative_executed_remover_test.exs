defmodule SeedFactory.FromAlternativeExecutedRemoverTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :wipe_e removes :t1 for sure and :restore_e re-declares both sources of
    # :closed under a condition reading the instance :wipe_e updates. The
    # refusal comes before :restore_e, once the re-add is known not to fire.
    command :make_e do
      resolve(fn _ -> {:ok, %{e: %{fresh: true}}} end)
      produce :e
    end

    command :make_stale_e do
      resolve(fn _ -> {:ok, %{e: %{fresh: false}}} end)
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

    command :close_e do
      param :e, entity: :e
      param :v, entity: :v
      resolve(fn _ -> {:ok, %{e: %{fresh: false}}} end)
      update :e
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

    trait :t2, :e do
      exec :restore_e,
        args_match: fn args -> args.e.fresh end,
        generate_args: fn -> %{} end
    end

    trait :closed, :e do
      from [:t1, :t2]
      exec :close_e
    end
  end

  use SeedFactory.Test, schema: Schema

  test "an executed step removed the only carried source", context do
    context = exec(context, :make_e)

    error =
      assert_raise SeedFactory.MissingRequestedTraitError,
                   "none of the source traits [:t1, :t2] required by :close_e would be present " <>
                     "on :e when it runs: command :wipe_e removed :t1 and no later planned " <>
                     "command applies any of them",
                   fn -> produce(context, e: [:closed]) end

    assert error.removed_by == :wipe_e
    assert error.removed_when == :executed
    assert error.removed_trait == :t1
  end

  test "no source was ever carried and the re-add does not fire", context do
    context = exec(context, :make_stale_e)

    error =
      assert_raise SeedFactory.MissingRequestedTraitError,
                   "none of the source traits [:t1, :t2] required by :close_e would be present " <>
                     "on :e when it runs: no planned command preserves or applies any of them",
                   fn -> produce(context, e: [:closed]) end

    assert error.removed_by == nil
    assert error.removed_trait == nil
  end
end
