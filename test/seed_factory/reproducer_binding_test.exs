defmodule SeedFactory.ReproducerBindingTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # e sits in the context, so :use_e's demand for it creates no edge; the
    # plan still deletes it for the receipt and re-produces it for the marker.
    # :use_e reads the new instance once the plan orders :remake_e before it.
    command :make_e do
      resolve(fn _ -> {:ok, %{e: :old}} end)

      produce :e
    end

    command :drop_e do
      param :e, entity: :e

      resolve(fn _ -> {:ok, %{receipt: :receipt1}} end)

      delete :e
      produce :receipt
    end

    command :remake_e do
      param :receipt, entity: :receipt

      resolve(fn _ -> {:ok, %{e: :new, marker: :marker1}} end)

      produce :e
      produce :marker
    end

    command :use_e do
      param :e, entity: :e
      param :receipt, entity: :receipt

      resolve(fn args -> {:ok, %{result: args.e}} end)

      produce :result
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a consumer of a deleted instance is ordered after the chosen re-producer", context do
    context = context |> exec(:make_e) |> produce([:result, :marker])

    assert context.result == :new
    assert context.e == :new
  end
end
