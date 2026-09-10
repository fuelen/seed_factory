defmodule SeedFactory.ConsumerTraitDeliveryTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :wipe_e strips :t1 under a pattern over a generated param, so the search
    # cannot judge the removal; the prediction before the execution can, once
    # the arguments are fixed. :use_e, planned after :wipe_e for :w, needs a
    # :t1 e and never gets one.
    command :make_e do
      resolve(fn _ ->
        send(self(), :made_e)
        {:ok, %{e: %{fresh: true}}}
      end)

      produce :e
    end

    command :wipe_e do
      param :e, entity: :e
      param :g, generate: fn -> :on end

      resolve(fn _ -> {:ok, %{e: %{fresh: false}, w: :w1}} end)

      update :e
      produce :w
    end

    command :use_e do
      param :e, entity: :e, with_traits: [:t1]
      param :w, entity: :w

      resolve(fn args ->
        send(self(), {:used_e, args.e})
        {:ok, %{u: :u1}}
      end)

      produce :u
    end

    command :use_e_early do
      param :e, entity: :e, with_traits: [:t1]

      resolve(fn args -> {:ok, %{q: args.e}} end)

      produce :q
    end

    trait :t1, :e do
      exec :make_e
    end

    trait :t9, :e do
      from :t1
      exec :wipe_e, args_pattern: %{g: :on}
    end

    # :restore_k re-declares :fresh under a condition reading the instance
    # :wipe_k updates, so the loss stays open until :wipe_k has run; the
    # refusal comes before :use_k, naming the executed remover.
    command :make_k do
      resolve(fn _ -> {:ok, %{k: %{fresh: true}}} end)

      produce :k
    end

    command :wipe_k do
      param :k, entity: :k
      param :g, generate: fn -> :on end

      resolve(fn _ ->
        send(self(), :wiped_k)
        {:ok, %{k: %{fresh: false}, x: :x1}}
      end)

      update :k
      produce :x
    end

    command :restore_k do
      param :k, entity: :k
      param :x, entity: :x

      resolve(fn _ -> {:ok, %{k: %{fresh: false}, y: :y1}} end)

      update :k
      produce :y
    end

    command :use_k do
      param :k, entity: :k, with_traits: [:fresh]
      param :y, entity: :y

      resolve(fn args ->
        send(self(), {:used_k, args.k})
        {:ok, %{z: :z1}}
      end)

      produce :z
    end

    trait :fresh, :k do
      exec :make_k
    end

    trait :stale, :k do
      from :fresh
      exec :wipe_k, args_pattern: %{g: :on}
    end

    trait :fresh, :k do
      exec :restore_k,
        args_match: fn args -> args.k.fresh end,
        generate_args: fn -> %{} end
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a removal the search cannot judge is refused before the plan runs", context do
    error =
      assert_raise SeedFactory.MissingRequestedTraitError,
                   "trait :t1 required by :use_e would be missing on :e when it runs: " <>
                     "command :wipe_e removes it",
                   fn -> produce(context, :u) end

    assert error.required_by == :use_e
    assert error.removed_by == :wipe_e
    assert error.removed_when == :planned
    refute_received :made_e
    refute_received {:used_e, _}
  end

  test "a removal after the consumer has run is not its business", context do
    context = produce(context, [:q, :w])

    assert context.q == %{fresh: true}
    refute :t1 in context.__seed_factory_meta__.current_traits.e
  end

  test "a removal followed by an uncertain re-add is refused before the consumer", context do
    error =
      assert_raise SeedFactory.MissingRequestedTraitError,
                   "trait :fresh required by :use_k would be missing on :k when it runs: " <>
                     "command :wipe_k removed it and no later planned command applies it",
                   fn -> produce(context, :z) end

    assert error.required_by == :use_k
    assert error.removed_by == :wipe_k
    assert error.removed_when == :executed
    assert_received :wiped_k
    refute_received {:used_k, _}
  end
end
