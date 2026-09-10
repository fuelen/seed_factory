defmodule SeedFactory.LosingDeclarationCommandTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :verified is reachable at creation and by :verify_user, which also
    # produces :badge. The creation declaration wins the trait and only the
    # declaration of :verify_user loses: the command stays a candidate for
    # :badge, runs with its own default args (the losing pattern rides no
    # edge), and a later demand for :verified reuses the winner.
    command :create_user do
      resolve(fn _ -> {:ok, %{user: :user1}} end)

      produce :user
    end

    command :verify_user do
      param :user, entity: :user
      param :method, value: :none

      resolve(fn args -> {:ok, %{user: :verified_user, badge: args.method}} end)

      update :user
      produce :badge
    end

    command :send_invoice do
      param :user, entity: :user, with_traits: [:verified]

      resolve(fn _ -> {:ok, %{invoice: :invoice1}} end)

      produce :invoice
    end

    trait :verified, :user do
      exec :create_user
    end

    trait :verified, :user do
      exec :verify_user, args_pattern: %{method: :email}
    end
  end

  use SeedFactory.Test, schema: Schema

  test "the command of a losing declaration stays available to other demands", context do
    # Was: "cannot produce entity :badge ... :verify_user lost the resolution
    # of another trait in this plan".
    context = produce(context, user: [:verified], badge: [])

    assert :verified in context.__seed_factory_meta__.current_traits.user
    assert context.badge == :none
  end

  test "a rider planned before the trait is resolved leaves the plan when it loses", context do
    context = produce(context, [:badge, user: [:verified]])

    assert context.badge == :none
    assert context.__seed_factory_meta__.current_traits.user == [:verified]
  end

  test "a later demand for the trait reuses the winner, not the losing declaration", context do
    context = produce(context, [{:user, [:verified]}, :badge, :invoice])

    assert context.invoice == :invoice1
    assert context.badge == :none
  end
end
