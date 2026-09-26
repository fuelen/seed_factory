defmodule SeedFactory.ParameterizedTraitStrictEqualityTest do
  use ExUnit.Case, async: true
  import SeedFactory

  defmodule Schema do
    use SeedFactory.Schema

    command :create_user do
      param :age, value: 30

      resolve(fn args -> {:ok, %{user: %{age: args.age}}} end)

      produce :user
    end

    command :celebrate do
      param :user, entity: :user
      param :age, value: 30

      resolve(fn args -> {:ok, %{user: %{args.user | age: args.age}, cake: :cake}} end)

      update :user
      produce :cake
    end

    trait :age, :user do
      exec :create_user, args_pattern: %{age: _}
    end

    trait :age, :user do
      exec :celebrate, args_pattern: %{age: _}
    end

    trait :float, :cake do
      exec :celebrate, args_pattern: %{age: 18.0}
    end
  end

  test "a value equal only under == does not keep a requested value" do
    ctx = produce(init(%{}, Schema), user: [age: 18])

    error =
      assert_raise SeedFactory.TraitResolutionError, fn ->
        produce(ctx, cake: [:float], user: [age: 18])
      end

    assert Exception.message(error) ==
             "cannot satisfy trait {:age, 18} for entity :user (requested trait)\n" <>
               "- command :celebrate, chosen for the plan, applies :age and removes {:age, 18}"
  end
end
