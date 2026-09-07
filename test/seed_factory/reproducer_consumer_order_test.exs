defmodule SeedFactory.ReproducerConsumerOrderTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # An existing :a, a deleter of :a, a re-producer of :a,
    # and a consumer fed by the re-producer through a SECOND entity (:b). The
    # only valid order is del_a -> remake_ab -> use_b: without ordering edges
    # anchored at the context instance the re-producer runs first on unlucky
    # command names and crashes with EntityAlreadyExistsError.
    command :create_a do
      resolve(fn _ -> {:ok, %{a: :a1}} end)

      produce :a
    end

    command :del_a do
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

    command :use_b do
      param :a, entity: :a
      param :b, entity: :b

      resolve(fn args -> {:ok, %{q: {args.a, args.b}}} end)

      produce :q
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a consumer fed by the re-producer does not trap the deleter after it", context do
    context = context |> produce(:a) |> produce([:x, :q])

    assert Map.has_key?(context, :x)
    assert context.q == {:a2, :b1}
    assert context.a == :a2
  end
end
