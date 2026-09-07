defmodule SeedFactory.PreProduceUnsatFullPlanTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Minimized from mixed-flow stress seeds 96/135/16/100. The full
    # produce([:target, :wanted]) plan is unsatisfiable: :target's only command
    # also produces :dep, while :wanted needs a :dep with the :fresh trait that
    # only :make_dep can provide - two producers of :dep, no deleter.
    #
    # pre_produce never executes the commands producing the requested entities,
    # so their effects must not fail the plan: the solver plans them as
    # phantoms and the conflict disappears with them.
    command :make_dep do
      resolve(fn _ -> {:ok, %{dep: :fresh_dep}} end)

      produce :dep
    end

    command :make_target do
      resolve(fn _ -> {:ok, %{target: :target, dep: :collateral_dep}} end)

      produce :target
      produce :dep
    end

    command :make_wanted do
      param :dep, entity: :dep, with_traits: [:fresh]

      resolve(fn _ -> {:ok, %{wanted: :wanted}} end)

      produce :wanted
    end

    command :make_dep_alt do
      resolve(fn _ -> {:ok, %{dep: :alt_dep}} end)

      produce :dep
    end

    command :make_picky do
      param :dep, entity: :dep, with_traits: [:fresh, :alt]

      resolve(fn _ -> {:ok, %{picky: :picky}} end)

      produce :picky
    end

    trait :fresh, :dep do
      exec :make_dep
    end

    trait :alt, :dep do
      exec :make_dep_alt
    end
  end

  use SeedFactory.Test, schema: Schema

  test "pre_produce prepares dependencies even when the full plan is unsatisfiable", context do
    context = pre_produce(context, [:target, :wanted])

    refute Map.has_key?(context, :target)
    refute Map.has_key?(context, :wanted)
    assert Map.has_key?(context, :dep)

    %{wanted: _} = produce(context, :wanted)
  end

  test "the request order does not matter: a real producer may precede the phantom", context do
    # :make_dep is chosen as a real dependency first, so the phantom
    # :make_target has to pass the viability check against it.
    context = pre_produce(context, [:wanted, :target])

    refute Map.has_key?(context, :target)
    refute Map.has_key?(context, :wanted)
    assert Map.has_key?(context, :dep)
  end

  test "a requested trait whose exec conflicts with a real producer is a phantom too", context do
    # :make_dep joins as a real dependency of :wanted, then the top-level
    # trait demand for :alt meets it: :make_dep_alt also produces :dep, but as
    # a phantom it cannot conflict.
    context = pre_produce(context, [:wanted, dep: [:alt]])

    refute Map.has_key?(context, :wanted)
  end

  test "unsatisfiable dependencies of the requested entity still fail loudly", context do
    # :picky itself is a phantom, but its parameter needs a :dep that is both
    # :fresh and :alt - two real producers of :dep, no deleter.
    assert_raise SeedFactory.TraitResolutionError, fn ->
      pre_produce(context, :picky)
    end
  end
end
