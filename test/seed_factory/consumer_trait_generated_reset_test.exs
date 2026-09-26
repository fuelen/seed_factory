defmodule SeedFactory.ConsumerTraitGeneratedResetTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :rep_d produces d anew for :sr after :del_d consumed the fresh one, and
    # its :fresh declaration reads a generated param. The search cannot judge
    # it, while the prediction before the first step already knows the fresh
    # instance comes without the trait.
    command :make_d do
      resolve(fn _ ->
        send(self(), :made_d)
        {:ok, %{d: :d1}}
      end)

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
      param :g, generate: fn -> :off end

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
      exec :rep_d, args_pattern: %{g: :on}
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a re-producer that generates args without the trait fails before the first step",
       context do
    assert_raise SeedFactory.MissingRequestedTraitError,
                 "trait :fresh required by :use_d would be missing on :d when it runs: " <>
                   "no planned command applies it",
                 fn -> produce(context, :sc) end

    refute_received :made_d
  end
end
