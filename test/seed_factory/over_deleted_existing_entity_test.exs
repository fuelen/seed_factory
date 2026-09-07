defmodule SeedFactory.OverDeletedExistingEntityTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # The context holds one :a and the
    # plan forces two deleters of it with no re-producer in between: only the
    # first deleter would find the instance alive, and accepting the plan
    # means EntityNotFoundError halfway through the execution.
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
  end

  use SeedFactory.Test, schema: Schema

  test "two deleters of a single context instance are refused loudly", context do
    context = produce(context, :a)

    error =
      assert_raise SeedFactory.UnproducibleEntityError, fn ->
        produce(context, [:x, :y])
      end

    assert error.entity == :a
    assert error.cause == :over_deleted
    assert Enum.sort(error.commands) == [:del_x, :del_y]

    assert error.message ==
             "cannot produce entity :a: it sits in the context once, " <>
               "but the plan deletes it more than once: #{inspect(error.commands)}"
  end

  test "a single deleter of the context instance stays legal", context do
    context = produce(context, :a)
    context = produce(context, [:x])

    assert context.x == :x1
    refute Map.has_key?(context, :a)
  end

  test "phantoms are exempt: pre_produce plans past both deleters", context do
    context = produce(context, :a)
    context = pre_produce(context, [:x, :y])

    refute Map.has_key?(context, :x)
    refute Map.has_key?(context, :y)
    assert context.a == :a1
  end
end
