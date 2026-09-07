defmodule SeedFactory.TrailingDeleterChainTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Two deleters of the same pre-existing entity with a
    # re-producer between them. Instances: a1 (context), a2 (remake_ab).
    # Valid order: del1 (eats a1) -> remake_ab (a2) -> del2 (eats a2). A chain
    # anchored at the context instance may end with a trailing deleter: the
    # final context simply loses the unrequested entity.
    command :create_a do
      resolve(fn _ -> {:ok, %{a: :a1}} end)

      produce :a
    end

    command :del1 do
      param :a, entity: :a

      resolve(fn _ -> {:ok, %{x: :x1}} end)

      produce :x
      delete :a
    end

    command :remake_ab do
      resolve(fn _ -> {:ok, %{a: :a2, b: :b1}} end)

      produce :a
      produce :b
    end

    command :del2 do
      param :a, entity: :a
      param :b, entity: :b

      resolve(fn _ -> {:ok, %{y: :y1}} end)

      produce :y
      delete :a
    end
  end

  use SeedFactory.Test, schema: Schema

  test "two deleters of an existing entity interleave with the re-producer", context do
    context = context |> produce(:a) |> produce([:x, :y])

    assert Map.has_key?(context, :x)
    assert Map.has_key?(context, :y)
    refute Map.has_key?(context, :a)
  end
end
