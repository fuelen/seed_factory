defmodule SeedFactory.ConsumerTraitResetTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :use_a needs a :fresh a and pr, and pr comes from :rep_a, which produces
    # a anew, without :fresh, after :del_a consumed the fresh one. Nothing can
    # feed :use_a a fresh a together with pr. The :b cluster has the same
    # shape plus :other_qr, a second source of qr that leaves b alone, so a
    # plan exists there once the search gives up on :rep_b. In the :c cluster
    # the re-producer declares :fresh itself, so the consumer reads a fresh
    # instance; in the :d cluster it declares :fresh under a condition on the
    # instance :del_d produces, which only the prediction can judge.
    command :make_a do
      resolve(fn _ -> {:ok, %{a: :a1}} end)

      produce :a
    end

    command :del_a do
      param :a, entity: :a

      resolve(fn _ -> {:ok, %{pd: :pd1}} end)

      delete :a
      produce :pd
    end

    command :rep_a do
      param :pd, entity: :pd

      resolve(fn _ -> {:ok, %{a: :a2, pr: :pr1}} end)

      produce :a
      produce :pr
    end

    command :use_a do
      param :a, entity: :a, with_traits: [:fresh]
      param :pr, entity: :pr

      resolve(fn args ->
        send(self(), {:used_a, args.a})
        {:ok, %{pc: args.a}}
      end)

      produce :pc
    end

    trait :fresh, :a do
      exec :make_a
    end

    command :make_b do
      resolve(fn _ -> {:ok, %{b: :b1}} end)

      produce :b
    end

    command :del_b do
      param :b, entity: :b

      resolve(fn _ -> {:ok, %{qd: :qd1}} end)

      delete :b
      produce :qd
    end

    command :rep_b do
      param :qd, entity: :qd

      resolve(fn _ -> {:ok, %{b: :b2, qr: :qr_from_rep}} end)

      produce :b
      produce :qr
    end

    command :other_qr do
      resolve(fn _ -> {:ok, %{qr: :qr_from_other}} end)

      produce :qr
    end

    command :use_b do
      param :b, entity: :b, with_traits: [:fresh]
      param :qr, entity: :qr

      resolve(fn args -> {:ok, %{qc: {args.b, args.qr}}} end)

      produce :qc
    end

    trait :fresh, :b do
      exec :make_b
    end

    command :make_c do
      resolve(fn _ -> {:ok, %{c: :c1}} end)

      produce :c
    end

    command :del_c do
      param :c, entity: :c

      resolve(fn _ -> {:ok, %{rd: :rd1}} end)

      delete :c
      produce :rd
    end

    command :rep_c do
      param :rd, entity: :rd

      resolve(fn _ -> {:ok, %{c: :c2, rr: :rr1}} end)

      produce :c
      produce :rr
    end

    command :use_c do
      param :c, entity: :c, with_traits: [:fresh]
      param :rr, entity: :rr

      resolve(fn args -> {:ok, %{rc: args.c}} end)

      produce :rc
    end

    trait :fresh, :c do
      exec :make_c
    end

    trait :fresh, :c do
      exec :rep_c
    end

    command :make_d do
      resolve(fn _ -> {:ok, %{d: :d1}} end)

      produce :d
    end

    command :del_d do
      param :d, entity: :d

      resolve(fn _ -> {:ok, %{sd: :sd1}} end)

      delete :d
      produce :sd
    end

    command :rep_d do
      param :sd, entity: :sd

      resolve(fn _ -> {:ok, %{d: :d2, sr: :sr1}} end)

      produce :d
      produce :sr
    end

    command :use_d do
      param :d, entity: :d, with_traits: [:fresh]
      param :sr, entity: :sr

      resolve(fn args -> {:ok, %{sc: args.d}} end)

      produce :sc
    end

    trait :fresh, :d do
      exec :make_d
    end

    trait :fresh, :d do
      exec :rep_d,
        args_match: fn args -> args.sd == :sd1 end,
        generate_args: fn -> %{} end
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a command re-producing the entity before the consumer fails the plan loudly", context do
    assert_raise SeedFactory.TraitResolutionError,
                 "cannot satisfy trait :fresh for entity :a (trait required by :use_a command)\n" <>
                   "- command :rep_a, chosen for the plan, re-produces :a without :fresh",
                 fn -> produce(context, :pc) end

    refute_received {:used_a, _}
  end

  test "the search moves on to a candidate that leaves the entity alone", context do
    context = produce(context, :qc)

    assert context.qc == {:b1, :qr_from_other}
    refute Map.has_key?(context, :qd)
  end

  test "a re-producer applying the trait itself is legal", context do
    context = produce(context, :rc)

    assert context.rc == :c2
    assert :fresh in context.__seed_factory_meta__.current_traits.c
  end

  test "a re-producer that may apply the trait is judged by the prediction", context do
    context = produce(context, :sc)

    assert context.sc == :d2
    assert :fresh in context.__seed_factory_meta__.current_traits.d
  end
end
