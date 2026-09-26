defmodule SeedFactory.ParameterizedTraitUncertainReplacementTest do
  use ExUnit.Case, async: true
  import SeedFactory

  defmodule Schema do
    use SeedFactory.Schema

    # :senior pins :adopt to age 40, so the plan keeps the existing age and
    # :adopt assigns another one. Whether its :age declaration fires depends
    # on the donor the plan creates first, so the loss shows only in the
    # prediction after :create_donor.
    command :create_user do
      param :age, value: 30

      resolve(fn args -> {:ok, %{user: %{age: args.age}}} end)

      produce :user
    end

    command :create_donor do
      param :kind, value: :adult

      resolve(fn args -> {:ok, %{donor: %{kind: args.kind}}} end)

      produce :donor
    end

    command :adopt do
      param :user, entity: :user
      param :donor, entity: :donor
      param :age, value: 30

      resolve(fn args ->
        send(self(), :adopted)
        {:ok, %{user: %{args.user | age: args.age}, pet: :pet}}
      end)

      update :user
      produce :pet
    end

    trait :age, :user do
      exec :create_user, args_pattern: %{age: _}
    end

    trait :age, :user do
      exec :adopt, args_pattern: %{age: _, donor: %{kind: :adult}}
    end

    trait :senior, :pet do
      exec :adopt, args_pattern: %{age: 40}
    end
  end

  test "a replacement that depends on an entity the plan creates is caught before it runs" do
    ctx = produce(init(%{}, Schema), user: [age: 18])

    error =
      assert_raise SeedFactory.MissingRequestedTraitError, fn ->
        produce(ctx, pet: [:senior], user: [age: 18])
      end

    assert Exception.message(error) ==
             "requested trait {:age, 18} would be missing on :user after the plan: " <>
               "command :adopt assigns 40 instead"

    refute_received :adopted
  end
end
