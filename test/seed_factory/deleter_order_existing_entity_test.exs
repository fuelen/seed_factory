defmodule SeedFactory.DeleterOrderExistingEntityTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Pre-existing hole (v0.8.2 failed identically). The
    # "consumers run before deleters" ordering pass used to discover siblings
    # only through shared plan nodes. When the contested entity is ALREADY in
    # the context, neither the deleter nor the consumer has a plan edge for
    # it, so no ordering link was created and the topological sort fell back
    # to map order of command names: renaming :del_a_make_x to :z_del_a_make_x
    # made this pass. The consumer crashed with a raw KeyError because
    # creation of dependencies is locked inside produce.
    command :create_a do
      resolve(fn _ -> {:ok, %{a: :a1}} end)

      produce :a
    end

    command :del_a_make_x do
      param :a, entity: :a

      resolve(fn _ -> {:ok, %{x: :x1}} end)

      produce :x
      delete :a
    end

    command :make_y do
      param :a, entity: :a

      resolve(fn _ -> {:ok, %{y: :y1}} end)

      produce :y
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a consumer of an existing entity runs before its deleter", context do
    context = context |> produce(:a) |> produce([:x, :y])

    assert Map.has_key?(context, :x)
    assert Map.has_key?(context, :y)
  end
end
