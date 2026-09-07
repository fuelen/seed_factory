defmodule SeedFactory.SelfConsumingProducerTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Minimized from f2 stress seed 27. :remake_a consumes
    # :a and produces :a without deleting it (the DSL forbids delete+produce
    # of one entity in one command), so as a plan node it can never run: the
    # parameter needs a live instance, the produce needs none. Plans refuse it
    # loudly; the command stays usable through exec with the parameter covered.
    command :create_a do
      resolve(fn _ -> {:ok, %{a: :a1}} end)

      produce :a
    end

    command :del_a do
      param :a, entity: :a

      resolve(fn _ -> {:ok, %{pd: :pd1}} end)

      produce :pd
      delete :a
    end

    command :remake_a do
      param :a, entity: :a

      resolve(fn args -> {:ok, %{a: {:remade, args.a}, pr: :pr1}} end)

      produce :a
      produce :pr
    end

    command :use_fresh do
      param :a, entity: :a, with_traits: [:fresh]

      resolve(fn args -> {:ok, %{q: args.a}} end)

      produce :q
    end

    trait :fresh, :a do
      exec :remake_a
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a producer consuming its own entity is refused loudly", context do
    context = produce(context, :a)

    error =
      assert_raise SeedFactory.UnproducibleEntityError, fn ->
        produce(context, [:pd, :pr])
      end

    assert error.entity == :pr
    assert error.commands == [:remake_a]
  end

  test "a phantom is exempt: pre_produce plans its dependencies", context do
    context = produce(context, :a)
    context = pre_produce(context, :pr)

    refute Map.has_key?(context, :pr)
    assert context.a == :a1
  end

  test "a trait declaration backed by such a producer is refused too", context do
    error =
      assert_raise SeedFactory.TraitResolutionError, fn ->
        produce(context, :q)
      end

    assert error.trait == :fresh
  end

  test "exec with the parameter covered still works", context do
    context = exec(context, :remake_a, a: :manual_a)

    assert context.a == {:remade, :manual_a}
    assert context.pr == :pr1
  end
end
