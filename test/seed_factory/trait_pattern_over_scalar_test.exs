defmodule SeedFactory.TraitPatternOverScalarTest do
  use ExUnit.Case, async: true
  import SeedFactory

  defmodule Schema do
    use SeedFactory.Schema

    # A nested pattern over a nil field must not match a scalar param, where
    # reading the field yields nil as well.
    command :create do
      param :payload, value: 5

      resolve(fn args -> {:ok, %{item: args.payload}} end)

      produce :item
    end

    command :touch do
      param :item, entity: :item
      param :payload, value: 5

      resolve(fn args -> {:ok, %{item: args.item, touched: :touched}} end)

      update :item
      produce :touched
    end

    trait :plain, :item do
      exec :create
    end

    trait :flagless, :item do
      exec :create, args_pattern: %{payload: %{flag: nil}}
    end

    trait :wiped, :item do
      from :plain
      exec :touch, args_pattern: %{payload: %{flag: nil}}
    end
  end

  test "execution does not apply a nested nil pattern to a scalar arg" do
    ctx = exec(init(%{}, Schema), :create)
    assert ctx.__seed_factory_meta__.current_traits == %{item: [:plain]}
  end

  test "planning does not expect a nested nil pattern to fire on a scalar arg" do
    ctx = init(%{}, Schema) |> produce(item: [:plain]) |> produce([:touched, item: [:plain]])
    assert ctx.__seed_factory_meta__.current_traits == %{item: [:plain], touched: []}
  end

  defmodule ReAddSchema do
    use SeedFactory.Schema

    command :create do
      resolve(fn _ -> {:ok, %{item: :item}} end)

      produce :item
    end

    command :touch do
      param :item, entity: :item
      param :payload, value: 5

      resolve(fn args ->
        send(self(), :touched)
        {:ok, %{item: args.item, touched: :touched}}
      end)

      update :item
      produce :touched
    end

    trait :plain, :item do
      exec :create
    end

    trait :wiped, :item do
      from :plain
      exec :touch
    end

    trait :plain, :item do
      exec :touch, args_pattern: %{payload: %{flag: nil}}
    end

    trait :scalar, :touched do
      exec :touch, args_pattern: %{payload: 5}
    end
  end

  test "a re-add a nested nil pattern cannot fire on a scalar arg does not save the trait" do
    assert_raise SeedFactory.TraitResolutionError,
                 "cannot satisfy trait :plain for entity :item (requested trait)\n" <>
                   "- command :touch, chosen for the plan, applies :wiped and removes :plain",
                 fn -> produce(init(%{}, ReAddSchema), touched: [:scalar], item: [:plain]) end

    refute_received :touched
  end
end
