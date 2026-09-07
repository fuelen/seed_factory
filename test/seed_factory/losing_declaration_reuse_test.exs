defmodule SeedFactory.LosingDeclarationReuseTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # The :verified declaration of :verify_user is listed first, but the trait
    # is won by reuse of :create_user, already chosen for the :user needed by
    # :profile. :verify_user still joins the plan for :badge. A later demand
    # for :verified (from :send_invoice) must skip the losing declaration even
    # though its command is chosen and listed first, or :verify_user would run
    # with the losing pattern's :email.
    command :verify_user do
      param :user, entity: :user
      param :method, value: :none

      resolve(fn args -> {:ok, %{user: :verified_user, badge: args.method}} end)

      update :user
      produce :badge
    end

    command :create_user do
      resolve(fn _ -> {:ok, %{user: :user1}} end)

      produce :user
    end

    command :onboard_user do
      param :user, entity: :user

      resolve(fn _ -> {:ok, %{user: :onboarded_user, profile: :profile1}} end)

      update :user
      produce :profile
    end

    command :send_invoice do
      param :user, entity: :user, with_traits: [:verified]

      resolve(fn _ -> {:ok, %{invoice: :invoice1}} end)

      produce :invoice
    end

    trait :verified, :user do
      exec :verify_user, args_pattern: %{method: :email}
    end

    trait :verified, :user do
      exec :create_user
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a losing declaration listed before the winner is skipped by a later demand", context do
    context = produce(context, [:profile, {:user, [:verified]}, :badge, :invoice])

    assert context.profile == :profile1
    assert context.invoice == :invoice1
    assert context.badge == :none
  end
end
