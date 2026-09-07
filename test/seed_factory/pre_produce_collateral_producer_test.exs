defmodule SeedFactory.PreProduceCollateralProducerTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Minimized from mixed-flow stress seeds 255/310. pre_produce never
    # produces the requested entities, and that includes collateral produces:
    # :make_x joins the plan as a real dependency of :b, but it also produces
    # the requested :a, so it is planned as a phantom and pruned. Otherwise
    # the requested :a would sneak into the context.
    #
    # :make_b2 keeps the :b demand a decision, so :a commits to :make_a before
    # :make_x enters the plan - the shape of the stress seeds.
    command :make_a do
      resolve(fn _ -> {:ok, %{a: :a}} end)

      produce :a
    end

    command :make_b do
      param :x, entity: :x
      param :y, entity: :y

      resolve(fn _ -> {:ok, %{b: :b}} end)

      produce :b
    end

    command :make_b2 do
      resolve(fn _ -> {:ok, %{b: :alt_b}} end)

      produce :b
    end

    command :make_x do
      resolve(fn _ -> {:ok, %{x: :x, a: :collateral_a}} end)

      produce :x
      produce :a
    end

    command :make_y do
      resolve(fn _ -> {:ok, %{y: :y}} end)

      produce :y
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a dependency collaterally producing a requested entity is pruned", context do
    context = pre_produce(context, [:a, :b])

    refute Map.has_key?(context, :a)
    refute Map.has_key?(context, :b)
    refute Map.has_key?(context, :x)
    assert Map.has_key?(context, :y)

    %{b: _} = produce(context, :b)
  end
end
