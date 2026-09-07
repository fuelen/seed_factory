defmodule SeedFactory.DeleterInterleaveTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :make_left and :make_right both produce :shared, but :make_right depends
    # (via :junk) on the deleter that consumes :shared. The only valid plan is
    # make_left -> consume_shared -> make_right and its dependency edges force
    # exactly that order. v0.8.2 planned and executed it. The unconditional
    # produce-exclusion invariant makes the two commands mutually exclusive
    # regardless of the deleter sitting between them.
    command :make_left do
      resolve(fn _ -> {:ok, %{left: :l, shared: :s1}} end)

      produce :left
      produce :shared
    end

    command :consume_shared do
      param :shared, entity: :shared

      resolve(fn _ -> {:ok, %{junk: :j}} end)

      produce :junk
      delete :shared
    end

    command :make_right do
      param :junk, entity: :junk

      resolve(fn _ -> {:ok, %{right: :r, shared: :s2}} end)

      produce :right
      produce :shared
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a deleter between two commands producing the same entity is a valid plan", context do
    context = produce(context, [:left, :right])

    assert Map.has_key?(context, :left)
    assert Map.has_key?(context, :right)
  end
end
