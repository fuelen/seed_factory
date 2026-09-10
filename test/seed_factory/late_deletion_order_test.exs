defmodule SeedFactory.LateDeletionOrderTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :audit reads e, so it has to run before :drop_e; :drop_e reads f, so it
    # has to run before :drop_f; :audit needs the receipt of :drop_f. No order
    # satisfies all three, and the plan is refused before any command runs.
    command :make_e do
      resolve(fn _ -> {:ok, %{e: :e1}} end)

      produce :e
    end

    command :make_f do
      resolve(fn _ -> {:ok, %{f: :f1}} end)

      produce :f
    end

    command :drop_e do
      param :e, entity: :e
      param :f, entity: :f

      resolve(fn _ ->
        send(self(), {:ran, :drop_e})
        {:ok, %{w: :w1}}
      end)

      delete :e
      produce :w
    end

    command :drop_f do
      param :f, entity: :f

      resolve(fn _ ->
        send(self(), {:ran, :drop_f})
        {:ok, %{receipt: :receipt1}}
      end)

      delete :f
      produce :receipt
    end

    command :audit do
      param :e, entity: :e
      param :receipt, entity: :receipt

      resolve(fn _ ->
        send(self(), {:ran, :audit})
        {:ok, %{audit: :audit1}}
      end)

      produce :audit
    end
  end

  use SeedFactory.Test, schema: Schema

  test "readers that cannot all run before the deleters fail the plan before anything runs",
       context do
    assert_raise SeedFactory.UnproducibleEntityError, fn -> produce(context, [:audit, :w]) end

    refute_received {:ran, _}
  end
end
