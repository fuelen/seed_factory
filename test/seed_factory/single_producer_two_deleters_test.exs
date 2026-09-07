defmodule SeedFactory.SingleProducerTwoDeletersTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # The plan produces :e once and consumes it twice:
    # nothing can interleave, and the second deleter would find no instance.
    command :create_e do
      resolve(fn _ -> {:ok, %{e: :e1}} end)

      produce :e
    end

    command :make_a do
      param :e, entity: :e

      resolve(fn _ -> {:ok, %{a: :a1}} end)

      produce :a
      delete :e
    end

    command :make_b do
      param :e, entity: :e

      resolve(fn _ -> {:ok, %{b: :b1}} end)

      produce :b
      delete :e
    end
  end

  use SeedFactory.Test, schema: Schema

  test "two deleters of a single produced instance are refused at planning", context do
    error =
      assert_raise SeedFactory.UnproducibleEntityError, fn ->
        produce(context, [:a, :b])
      end

    assert error.entity == :e
    assert error.cause == :unorderable
    assert error.commands == [:create_e]

    assert error.message ==
             "cannot produce entity :e: the commands producing and deleting it cannot interleave " <>
               "produce → delete → produce: [:create_e]"
  end

  test "a single deleter of a single produced instance stays legal", context do
    context = produce(context, :a)

    assert context.a == :a1
    refute Map.has_key?(context, :e)
  end

  test "phantoms are exempt: pre_produce plans past both deleters", context do
    context = pre_produce(context, [:a, :b])

    assert context.e == :e1
    refute Map.has_key?(context, :a)
    refute Map.has_key?(context, :b)
  end
end
