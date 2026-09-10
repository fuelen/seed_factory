defmodule SeedFactory.PrunedCandidateTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # With x in the context, :make_e_and_x would duplicate it, unless a deleter
    # of x runs first: :consume_x, planned for y, does exactly that. :copy_e,
    # the other route to e, can never run as a dependency. Whether
    # :make_e_and_x fits is therefore known only once the plan is: the
    # collector keeps it, the search decides.
    command :make_x do
      resolve(fn _ -> {:ok, %{x: :old}} end)

      produce :x
    end

    command :make_e_and_x do
      resolve(fn _ -> {:ok, %{e: :e1, x: :new}} end)

      produce :e
      produce :x
    end

    command :copy_e do
      param :e, entity: :e

      resolve(fn args -> {:ok, %{e: args.e}} end)

      produce :e
    end

    command :consume_x do
      param :x, entity: :x

      resolve(fn _ -> {:ok, %{y: :y1}} end)

      delete :x
      produce :y
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a candidate duplicating an entity is kept for the deleter that legalizes it", context do
    context = context |> exec(:make_x) |> produce([:e, :y])

    assert context.e == :e1
    assert context.y == :y1
    assert context.x == :new
  end

  test "without the deleter the duplicate is refused, and the report names it", context do
    context = exec(context, :make_x)

    assert_raise SeedFactory.UnproducibleEntityError,
                 "cannot produce entity :e: no candidate command fits the plan\n" <>
                   "- :make_e_and_x would duplicate existing :x (rebind or delete it first)\n" <>
                   "- :copy_e both requires and produces :e, so it can never run as a dependency",
                 fn -> produce(context, :e) end
  end
end
