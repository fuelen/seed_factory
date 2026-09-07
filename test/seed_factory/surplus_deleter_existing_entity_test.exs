defmodule SeedFactory.SurplusDeleterExistingEntityTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # A chain anchored at the context instance supports one deleter per
    # instance at most: with three forced deleters and only two instances
    # (context + :remake_ab) the plan is refused loudly. The error names the
    # real commands only - the virtual context instance stays internal.
    command :create_a do
      resolve(fn _ -> {:ok, %{a: :a1}} end)

      produce :a
    end

    command :del_x do
      param :a, entity: :a

      resolve(fn _ -> {:ok, %{x: :x1}} end)

      produce :x
      delete :a
    end

    command :del_y do
      param :a, entity: :a

      resolve(fn _ -> {:ok, %{y: :y1}} end)

      produce :y
      delete :a
    end

    command :del_z do
      param :a, entity: :a

      resolve(fn _ -> {:ok, %{z: :z1}} end)

      produce :z
      delete :a
    end

    command :remake_ab do
      resolve(fn _ -> {:ok, %{a: :a2, b: :b1}} end)

      produce :a
      produce :b
    end
  end

  use SeedFactory.Test, schema: Schema

  test "three deleters cannot fit two instances of an existing entity", context do
    context = exec(context, :create_a)

    error =
      assert_raise SeedFactory.UnproducibleEntityError, fn ->
        produce(context, [:x, :y, :z, :b])
      end

    assert error.entity == :a
    assert error.commands == [:remake_ab]
  end
end
