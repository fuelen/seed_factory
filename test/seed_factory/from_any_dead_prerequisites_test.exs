defmodule SeedFactory.FromAnyDeadPrerequisitesTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Both from options of :final are dead on this entity: :process ran without
    # matching either args pattern. The error reports the first option, as it
    # represents the preferred route.
    command :create_item do
      resolve(fn _ -> {:ok, %{item: :new_item}} end)

      produce :item
    end

    command :process do
      param :item, entity: :item
      param :mode, value: :x

      resolve(fn _ -> {:ok, %{item: :processed_item}} end)

      update :item
    end

    command :finish do
      param :item, entity: :item

      resolve(fn _ -> {:ok, %{item: :final_item}} end)

      update :item
    end

    trait :path_a, :item do
      exec :process, args_pattern: %{mode: :a}
    end

    trait :path_b, :item do
      exec :process, args_pattern: %{mode: :b}
    end

    trait :final, :item do
      from [:path_a, :path_b]
      exec :finish
    end
  end

  use SeedFactory.Test, schema: Schema

  test "raises for the first from option when every option mismatches the trail", context do
    context =
      context
      |> produce(:item)
      |> exec(:process, mode: :x)

    error =
      assert_raise SeedFactory.TraitResolutionError, fn ->
        produce(context, item: [:final])
      end

    assert error.trait == :final
    assert error.message =~ "prerequisite trait :path_a required by :final cannot be satisfied"
    assert error.message =~ "traits of previously executed command :process do not match"
    refute error.message =~ ":path_b"
  end
end
