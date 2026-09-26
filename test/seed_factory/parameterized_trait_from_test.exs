defmodule SeedFactory.ParameterizedTraitFromTest do
  use ExUnit.Case, async: true
  import SeedFactory

  defmodule Schema do
    use SeedFactory.Schema

    command :create_user do
      param :age, value: 30

      resolve(fn args -> {:ok, %{user: %{age: args.age, status: :pending}}} end)

      produce :user
    end

    command :verify do
      param :user, entity: :user
      param :age

      resolve(fn args -> {:ok, %{user: %{args.user | age: args.age, status: :verified}}} end)

      update :user
    end

    trait :pending, :user do
      exec :create_user
    end

    trait :age, :user do
      from :pending
      exec :verify, args_pattern: %{age: _}
    end
  end

  test "a value assigned through a transition blocks its source trait later" do
    ctx = produce(init(%{}, Schema), user: [age: 18])
    assert ctx.__seed_factory_meta__.current_traits.user == [age: 18]

    assert_raise SeedFactory.TraitRemovedByCommandError,
                 "cannot apply traits [:pending] to :user because they were removed by command :verify, " <>
                   "current traits: [age: 18]",
                 fn -> produce(ctx, user: [:pending]) end
  end

  test "a value that replaces a trait requested with it is refused before planning" do
    for operation <- [&produce/2, &pre_produce/2] do
      assert_raise SeedFactory.TraitRestrictionConflictError,
                   "cannot apply traits [age: 18] to :user, requested with the traits [:pending, {:age, 18}]: " <>
                     "applying them would replace a requested trait",
                   fn -> operation.(init(%{}, Schema), user: [:pending, age: 18]) end
    end
  end
end
