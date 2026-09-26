defmodule SeedFactory.ParameterizedTraitResetTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :del_a consumes the a that :make_a created with the requested value, and
    # :rep_a produces a anew for :pr. Both :rep_a declarations read the value
    # from the instance :del_a produces, so only the prediction before the
    # plan runs can see that neither assigns it.
    command :make_a do
      param :v, value: 18

      resolve(fn args -> {:ok, %{a: %{v: args.v}}} end)

      produce :a
    end

    command :del_a do
      param :a, entity: :a

      resolve(fn _ -> {:ok, %{pd: %{kind: :y}}} end)

      delete :a
      produce :pd
    end

    command :rep_a do
      param :pd, entity: :pd
      param :w, generate: fn -> 21 end

      resolve(fn _ ->
        send(self(), :rep_a_executed)
        {:ok, %{a: %{v: nil}, pr: :pr1}}
      end)

      produce :a
      produce :pr
    end

    command :use_a do
      param :a, entity: :a, with_traits: [property: 18]
      param :pr, entity: :pr

      resolve(fn args -> {:ok, %{pc: args.a}} end)

      produce :pc
    end

    command :use_a_nil do
      param :a, entity: :a, with_traits: [property: nil]
      param :pr, entity: :pr

      resolve(fn args -> {:ok, %{pn: args.a}} end)

      produce :pn
    end

    command :use_a_weighted do
      param :a, entity: :a, with_traits: [weight: 18]
      param :pr, entity: :pr

      resolve(fn args -> {:ok, %{pw: args.a}} end)

      produce :pw
    end

    trait :property, :a do
      exec :make_a, args_pattern: %{v: _}
    end

    trait :property, :a do
      exec :rep_a, args_pattern: %{pd: %{v: _}}
    end

    trait :weight, :a do
      exec :make_a, args_pattern: %{v: _}
    end

    trait :weight, :a do
      exec :rep_a, args_pattern: %{pd: %{kind: :x}, w: _}
    end
  end

  test "a re-producer whose args lack the placeholder path does not assign the value" do
    context = SeedFactory.init(%{}, Schema)

    error =
      assert_raise SeedFactory.MissingRequestedTraitError, fn ->
        SeedFactory.produce(context, :pc)
      end

    assert Exception.message(error) ==
             "trait {:property, 18} required by :use_a would be missing on :a when it runs: " <>
               "no planned command applies it"
  end

  test "a re-producer with a mismatched fixed field does not assign the value" do
    context = SeedFactory.init(%{}, Schema)

    error =
      assert_raise SeedFactory.MissingRequestedTraitError, fn ->
        SeedFactory.produce(context, :pw)
      end

    assert Exception.message(error) ==
             "trait {:weight, 18} required by :use_a_weighted would be missing on :a when it runs: " <>
               "no planned command applies it"
  end

  test "a nil value the re-producer reads from an absent field is not assigned" do
    context = SeedFactory.init(%{}, Schema)

    error =
      assert_raise SeedFactory.MissingRequestedTraitError, fn ->
        SeedFactory.produce(context, :pn)
      end

    assert Exception.message(error) ==
             "trait {:property, nil} required by :use_a_nil would be missing on :a when it runs: " <>
               "no planned command applies it"

    refute_received :rep_a_executed
  end
end
