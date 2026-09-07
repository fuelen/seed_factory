defmodule SeedFactory.ReproducerOrderExistingEntityTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Pre-existing hole (v0.8.2 failed identically), third
    # form: an entity sitting in the context is its first instance, so a
    # command re-producing it can only run after the deleter that removes it.
    # Without the ordering link the re-producer ran first whenever its name
    # sorted before the deleter's and crashed with EntityAlreadyExistsError.
    command :create_a do
      resolve(fn _ -> {:ok, %{a: :a1}} end)

      produce :a
    end

    command :make_b_and_a do
      resolve(fn _ -> {:ok, %{b: :b1, a: :a2}} end)

      produce :b
      produce :a
    end

    command :z_del_a_make_x do
      param :a, entity: :a

      resolve(fn _ -> {:ok, %{x: :x1}} end)

      produce :x
      delete :a
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a re-producer of an existing entity runs after its deleter", context do
    context = context |> produce(:a) |> produce([:x, :b])

    assert Map.has_key?(context, :x)
    assert Map.has_key?(context, :b)
    # the deleter consumed :a1, then the re-producer put :a2 in its place
    assert context.a == :a2
  end
end
