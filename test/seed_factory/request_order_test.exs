defmodule SeedFactory.RequestOrderTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # A request is a set: the search reads it in one canonical order, so the
    # plan, and with it the traits nobody asked for, does not depend on how
    # the request is written. e2 comes from :c1 alone, with :t1, or from :c2
    # together with e1; :c1 is declared first.
    command :c1 do
      resolve(fn _ -> {:ok, %{e2: :from_c1}} end)

      produce :e2
    end

    command :c2 do
      resolve(fn _ -> {:ok, %{e1: :from_c2, e2: :from_c2}} end)

      produce :e1
      produce :e2
    end

    command :c4 do
      resolve(fn _ -> {:ok, %{e1: :from_c4}} end)

      produce :e1
    end

    command :tag_e1 do
      param :e1, entity: :e1
      param :kind, value: :none

      resolve(fn args -> {:ok, %{e1: {:tagged, args.kind}}} end)

      update :e1
    end

    trait :t1, :e2 do
      exec :c1
    end

    trait :ta, :e1 do
      exec :tag_e1, args_pattern: %{kind: :a}
    end

    trait :tb, :e1 do
      exec :tag_e1, args_pattern: %{kind: :b}
    end
  end

  use SeedFactory.Test, schema: Schema

  test "the order of the requested entities does not change the plan", context do
    [first, second] = for request <- [[:e1, :e2], [:e2, :e1]], do: produce(context, request)

    assert first.e1 == second.e1
    assert first.e2 == second.e2

    assert first.__seed_factory_meta__.current_traits ==
             second.__seed_factory_meta__.current_traits
  end

  test "the order of the requested traits does not change the failure", context do
    messages =
      for traits <- [[:ta, :tb], [:tb, :ta]] do
        error =
          assert_raise SeedFactory.TraitResolutionError, fn -> produce(context, e1: traits) end

        error.message
      end

    assert [message, message] = messages
  end
end
