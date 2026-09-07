defmodule SeedFactory.PreProduceProtectedRequestTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # pre_produce plans exactly like produce, it only skips executing the
    # requested entities' commands. The protection of requested entities is
    # shared: a request never consumes what it names. Here :forge needs an
    # :ember and the only way to an :ember eats the :relic.
    command :make_relic do
      resolve(fn _ -> {:ok, %{relic: :relic}} end)

      produce :relic
    end

    command :make_forge do
      param :ember, entity: :ember

      resolve(fn _ -> {:ok, %{forge: :forge}} end)

      produce :forge
    end

    command :make_ember do
      resolve(fn _ -> {:ok, %{ember: :ember}} end)

      produce :ember
      delete :relic
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a requested entity is protected from deletion, exactly as in produce", context do
    context = exec(context, :make_relic)

    assert_raise SeedFactory.UnproducibleEntityError, fn ->
      pre_produce(context, [:relic, :forge])
    end

    assert_raise SeedFactory.UnproducibleEntityError, fn ->
      produce(context, [:relic, :forge])
    end
  end

  test "an entity absent from the request may be consumed, exactly as in produce", context do
    context = exec(context, :make_relic)
    context = pre_produce(context, [:forge])

    refute Map.has_key?(context, :forge)
    refute Map.has_key?(context, :relic)
    assert Map.has_key?(context, :ember)

    %{forge: _} = produce(context, :forge)
  end
end
