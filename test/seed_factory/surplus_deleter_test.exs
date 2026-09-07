defmodule SeedFactory.SurplusDeleterTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Two producers of :shared and two chosen deleters of it. Supported chains
    # end with a producer (produce -> delete -> ... -> produce), so the second
    # deleter fits nowhere and the request is refused loudly instead of
    # leaving the surplus deleter unordered.
    command :make_left do
      resolve(fn _ -> {:ok, %{left: :l, shared: :s1}} end)

      produce :left
      produce :shared
    end

    command :make_right do
      resolve(fn _ -> {:ok, %{right: :r, shared: :s2}} end)

      produce :right
      produce :shared
    end

    command :burn_one do
      param :shared, entity: :shared

      resolve(fn _ -> {:ok, %{ash_one: :ash_one}} end)

      produce :ash_one
      delete :shared
    end

    command :burn_two do
      param :shared, entity: :shared

      resolve(fn _ -> {:ok, %{ash_two: :ash_two}} end)

      produce :ash_two
      delete :shared
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a deleter that fits between no producers refuses the plan", context do
    assert_raise SeedFactory.UnproducibleEntityError, fn ->
      produce(context, [:left, :right, :ash_one, :ash_two])
    end
  end
end
