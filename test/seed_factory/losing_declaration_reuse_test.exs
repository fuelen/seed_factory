defmodule SeedFactory.LosingDeclarationReuseTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # The :verified declaration of :verify_account is listed first, but the
    # account is demanded before the trait is decided, so :create_account is
    # chosen first and the trait reuses it. :verify_account still joins the
    # plan for :badge. A later demand for :verified (from :send_invoice) must
    # skip the losing declaration even though its command is chosen and listed
    # first, or :verify_account would run with the losing pattern's :email.
    command :verify_account do
      param :account, entity: :account
      param :method, value: :none

      resolve(fn args -> {:ok, %{account: :verified_account, badge: args.method}} end)

      update :account
      produce :badge
    end

    command :create_account do
      resolve(fn _ -> {:ok, %{account: :account1}} end)

      produce :account
    end

    command :onboard_account do
      param :account, entity: :account

      resolve(fn _ -> {:ok, %{account: :onboarded_account, profile: :profile1}} end)

      update :account
      produce :profile
    end

    command :send_invoice do
      param :account, entity: :account, with_traits: [:verified]

      resolve(fn _ -> {:ok, %{invoice: :invoice1}} end)

      produce :invoice
    end

    trait :verified, :account do
      exec :verify_account, args_pattern: %{method: :email}
    end

    trait :verified, :account do
      exec :create_account
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a losing declaration listed before the winner is skipped by a later demand", context do
    context = produce(context, [:profile, {:account, [:verified]}, :badge, :invoice])

    assert context.profile == :profile1
    assert context.invoice == :invoice1
    assert context.badge == :none
  end
end
