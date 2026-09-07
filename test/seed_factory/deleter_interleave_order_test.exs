defmodule SeedFactory.DeleterInterleaveOrderTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Unlike the chain of DeleterInterleaveTest, nothing forces :make_right to
    # run after :consume_both here: the planner itself must order the second
    # producer of :shared and :extra behind the deleter.
    command :make_left do
      resolve(fn _ -> {:ok, %{left: :l, shared: :s1, extra: :x1}} end)

      produce :left
      produce :shared
      produce :extra
    end

    command :make_right do
      resolve(fn _ -> {:ok, %{right: :r, shared: :s2, extra: :x2}} end)

      produce :right
      produce :shared
      produce :extra
    end

    command :consume_both do
      param :shared, entity: :shared

      resolve(fn _ -> {:ok, %{junk: :j}} end)

      produce :junk
      delete :shared
      delete :extra
    end

    command :make_junk do
      resolve(fn _ -> {:ok, %{junk: :plain_junk}} end)

      produce :junk
    end

    trait :plain, :junk do
      exec :make_junk
    end
  end

  use SeedFactory.Test, schema: Schema

  test "the second producer is ordered behind the deleter", context do
    context = produce(context, [:left, :right, :junk])

    assert Map.has_key?(context, :left)
    assert Map.has_key?(context, :right)
    assert context.shared == :s2
    assert context.extra == :x2
  end

  test "two producers without the deleter between them are refused", context do
    # The :plain trait takes :junk away from the deleter, so nothing can sit
    # between the two producers of :shared.
    assert_raise SeedFactory.UnproducibleEntityError, fn ->
      produce(context, [:left, :right, junk: [:plain]])
    end
  end
end
