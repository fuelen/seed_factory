defmodule SeedFactory.ConsumedInstanceTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Minimized from from_any stress seed 134. A requested entity has to sit in
    # the final context, so :burn_prize (the only way to :token) can never join
    # a plan that also has to keep the requested :prize, no matter which
    # instance it would consume. Refusing loudly beats the old silent context
    # without the sealed prize.
    command :make_prize do
      resolve(fn _ -> {:ok, %{prize: :sealed_prize}} end)

      produce :prize
    end

    command :burn_prize do
      param :prize, entity: :prize

      resolve(fn _ -> {:ok, %{token: :token}} end)

      produce :token
      delete :prize
    end

    command :make_extra do
      resolve(fn _ -> {:ok, %{extra: :extra, prize: :unsealed_prize}} end)

      produce :extra
      produce :prize
    end

    trait :sealed, :prize do
      exec :make_prize
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a deleter of a requested entity fails the plan loudly", context do
    # Was: a context whose :prize silently lacked the requested :sealed trait.
    assert_raise SeedFactory.UnproducibleEntityError, fn ->
      produce(context, [{:prize, [:sealed]}, :token, :extra])
    end

    assert_raise SeedFactory.UnproducibleEntityError, fn ->
      produce(context, [{:prize, [:sealed]}, :token])
    end

    assert_raise SeedFactory.UnproducibleEntityError, fn ->
      produce(context, [:prize, :token])
    end
  end

  test "the deleter is fine while its victim is not requested", context do
    context = produce(context, [:token, :extra])

    assert Map.has_key?(context, :token)
    assert Map.has_key?(context, :extra)
    refute Map.has_key?(context, :prize)
  end
end
