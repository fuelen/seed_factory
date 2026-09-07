defmodule SeedFactory.UnproducibleRejectionReasonsTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # A mixed refusal: one candidate for :thing dies on a stored parameter
    # check (its :user parameter needs :active, a transition past the
    # requested :pending), the other on a produce conflict. Both reasons land
    # in one UnproducibleEntityError, each candidate with its own line.
    command :create_user do
      resolve(fn _ -> {:ok, %{user: :pending_user}} end)

      produce :user
    end

    command :activate_user do
      param :user, entity: :user

      resolve(fn _ -> {:ok, %{user: :active_user}} end)

      update :user
    end

    command :make_collateral do
      resolve(fn _ -> {:ok, %{collateral: :collateral}} end)

      produce :collateral
    end

    command :thing_via_active do
      param :user, entity: :user, with_traits: [:active]

      resolve(fn _ -> {:ok, %{thing: :thing_a}} end)

      produce :thing
    end

    command :thing_other do
      resolve(fn _ -> {:ok, %{thing: :thing_b, collateral: :collateral_b}} end)

      produce :thing
      produce :collateral
    end

    trait :pending, :user do
      exec :create_user
    end

    trait :active, :user do
      from :pending
      exec :activate_user
    end

    trait :fresh, :collateral do
      exec :make_collateral
    end
  end

  use SeedFactory.Test, schema: Schema

  test "every rejected candidate gets its own reason line", context do
    error =
      assert_raise SeedFactory.UnproducibleEntityError, fn ->
        produce(context, [{:collateral, [:fresh]}, :thing, user: [:pending]])
      end

    assert error.message == """
           cannot produce entity :thing: no candidate command fits the plan
           - :thing_via_active was rejected by a parameter check (TraitRestrictionConflictError)
           - :thing_other also produces :collateral, already produced by :make_collateral in this plan\
           """
  end
end
