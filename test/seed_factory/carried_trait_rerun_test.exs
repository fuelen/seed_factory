defmodule SeedFactory.CarriedTraitRerunTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    command :create_user do
      resolve(fn _ -> {:ok, %{user: :user}} end)
      produce :user
    end

    command :tag_user do
      param :user, entity: :user
      param :mode, value: :a
      resolve(fn args -> {:ok, %{user: args.user}} end)
      update :user
    end

    command :approve_user do
      param :user, entity: :user
      resolve(fn args -> {:ok, %{user: args.user}} end)
      update :user
    end

    trait :pending, :user do
      exec :create_user
    end

    trait :tagged, :user do
      exec :tag_user, args_pattern: %{mode: :a}
    end

    trait :approved, :user do
      from :tagged
      exec :approve_user
    end
  end

  use SeedFactory.Test, schema: Schema
  import TraitAssertions

  test "a carried source applied by a later run of a command", context do
    context =
      context
      |> produce(:user)
      |> exec(:tag_user, mode: :b)
      |> exec(:tag_user, mode: :a)
      |> produce(user: [:approved])

    assert_trait(context, :user, [:pending, :approved])
  end
end
