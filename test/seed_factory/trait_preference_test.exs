defmodule SeedFactory.TraitPreferenceTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :make_e_alt is the first declared command producing :e, but requesting
    # f: [:special] prefers :make_f_combo for :e, since it produces both
    # entities. The full candidate list is registered with the preferred
    # command first, so the preference decides the resolution while the
    # alternative stays available.
    command :make_e_alt do
      resolve(fn _ -> {:ok, %{e: :e_alt}} end)

      produce :e
    end

    command :make_f1 do
      resolve(fn _ -> {:ok, %{f: :f1, g: :g1}} end)

      produce :f
      produce :g
    end

    command :make_f_combo do
      resolve(fn _ -> {:ok, %{f: :f_combo, e: :e_combo}} end)

      produce :f
      produce :e
    end

    command :use_e do
      param :e, entity: :e

      resolve(fn args -> {:ok, %{r: {:r, args.e}}} end)

      produce :r
    end

    command :use_e_alt do
      resolve(fn _ -> {:ok, %{r: :r_alt}} end)

      produce :r
    end

    command :use_g do
      param :g, entity: :g

      resolve(fn args -> {:ok, %{h: {:h, args.g}}} end)

      produce :h
    end

    command :use_g_alt do
      resolve(fn _ -> {:ok, %{h: :h_alt}} end)

      produce :h
    end

    trait :special, :f do
      exec :make_f1
    end

    trait :special, :f do
      exec :make_f_combo
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a trait-preferred command wins over the declaration order", context do
    context = produce(context, [:r, f: [:special]])

    assert context.f == :f_combo
    assert context.e == :e_combo
    assert context.r == {:r, :e_combo}
  end

  test "the plan falls back to another command when the preferred one dies", context do
    # The demand for :g forces :make_f1, killing :make_f_combo, so :e must come
    # from :make_e_alt. Was: the preferred command was the only registered
    # candidate and its death made :e unproducible.
    context = produce(context, [:r, :h, f: [:special]])

    assert context.f == :f1
    assert context.e == :e_alt
    assert context.r == {:r, :e_alt}
    assert context.h == {:h, :g1}
  end
end
