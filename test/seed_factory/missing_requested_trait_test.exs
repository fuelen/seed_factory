defmodule SeedFactory.MissingRequestedTraitTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # The contract of produce: every requested trait is on its entity
    # afterwards. Whether :update_user keeps :active depends on the status its
    # :premium declaration generates, and :verify_user's declaration never
    # matches the args it generates. The args are fixed before the execution,
    # so both losses are predicted and refused before any command runs. The
    # :member conditions read the instance the plan itself creates, so they
    # are judged right before their command, once the instance exists. The
    # :card cluster re-adds through such a condition written as a pattern
    # match, which would answer falsely on an unknown value, and
    # :demote_member changes the instance an earlier prediction would
    # otherwise trust.
    command :create_user do
      resolve(fn _ -> {:ok, %{user: %{tier: :bronze}}} end)

      produce :user
    end

    command :update_user do
      param :user, entity: :user
      param :plan, value: :free
      param :status, value: :active

      resolve(fn _ -> {:ok, %{user: %{tier: :bronze}}} end)

      update :user
    end

    command :verify_user do
      param :user, entity: :user
      param :method, value: :email

      resolve(fn _ -> {:ok, %{user: %{tier: :bronze}}} end)

      update :user
    end

    command :send_invoice do
      param :user, entity: :user, with_traits: [:verified]

      resolve(fn _ -> {:ok, %{invoice: :invoice1}} end)

      produce :invoice
    end

    command :create_member do
      resolve(fn _ -> {:ok, %{member: %{tier: :gold}}} end)

      produce :member
    end

    command :promote_member do
      param :member, entity: :member

      resolve(fn _ -> {:ok, %{member: %{tier: :gold}}} end)

      update :member
    end

    command :demote_member do
      param :member, entity: :member

      resolve(fn _ -> {:ok, %{member: %{tier: :silver}}} end)

      update :member
    end

    command :promote_after_demotion do
      param :member, entity: :member, with_traits: [:demoted]

      resolve(fn _ -> {:ok, %{member: %{tier: :gold}}} end)

      update :member
    end

    command :create_card do
      resolve(fn _ -> {:ok, %{card: %{level: 5}}} end)

      produce :card
    end

    command :stamp_card do
      param :card, entity: :card

      resolve(fn _ -> {:ok, %{card: %{level: 5}}} end)

      update :card
    end

    trait :active, :user do
      exec :create_user
    end

    trait :active, :user do
      exec :update_user, args_pattern: %{status: :active}
    end

    trait :blocked, :user do
      from :active
      exec :update_user, args_pattern: %{status: :blocked}
    end

    trait :premium, :user do
      exec :update_user,
        args_match: fn args -> args.plan != :free end,
        generate_args: fn -> %{plan: :pro, status: :blocked} end
    end

    trait :verified, :user do
      exec :verify_user,
        args_match: fn args -> args.user.tier == :bronze and args.method == :sms end,
        generate_args: fn -> %{method: :email} end
    end

    trait :active, :member do
      exec :create_member
    end

    trait :gold_only, :member do
      from :active

      exec :promote_member,
        args_match: fn args -> args.member.tier == :gold end,
        generate_args: fn -> %{} end
    end

    trait :noted, :member do
      exec :promote_member
    end

    trait :legend, :member do
      exec :create_member,
        args_match: fn _args -> false end,
        generate_args: fn -> %{} end
    end

    trait :platinum, :member do
      exec :promote_member,
        args_match: fn args -> args.member.tier == :platinum end,
        generate_args: fn -> %{} end
    end

    trait :demoted, :member do
      exec :demote_member
    end

    trait :gold_only, :member do
      from :active

      exec :promote_after_demotion,
        args_match: fn args -> args.member.tier == :gold end,
        generate_args: fn -> %{} end
    end

    trait :reconsidered, :member do
      exec :promote_after_demotion
    end

    trait :fresh, :card do
      exec :create_card
    end

    trait :fresh, :card do
      exec :stamp_card,
        args_match: fn args -> match?(%{level: 5}, args.card) end,
        generate_args: fn -> %{} end
    end

    trait :stamped, :card do
      from :fresh
      exec :stamp_card
    end

    trait :noted_card, :card do
      exec :stamp_card
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a requested trait a planned command removes is refused before the execution", context do
    context = exec(context, :create_user)

    # Was: a context whose user was blocked while :active was requested.
    assert_raise SeedFactory.MissingRequestedTraitError,
                 "requested trait :active would be missing on :user after the plan: " <>
                   "command :update_user removes it",
                 fn ->
                   produce(context, user: [:active, :premium])
                 end
  end

  test "a requested trait no planned command applies is refused before the execution", context do
    context = exec(context, :create_user)

    assert_raise SeedFactory.MissingRequestedTraitError,
                 "requested trait :verified would be missing on :user after the plan: " <>
                   "no planned command applies it",
                 fn ->
                   produce(context, user: [:verified])
                 end
  end

  test "the dependencies of exec are checked the same way", context do
    context = exec(context, :create_user)

    assert_raise SeedFactory.MissingRequestedTraitError,
                 "requested trait :verified would be missing on :user after the plan: " <>
                   "no planned command applies it",
                 fn ->
                   exec(context, :send_invoice)
                 end
  end

  test "the message names the binding when the entity is rebound", context do
    assert_raise SeedFactory.MissingRequestedTraitError,
                 "requested trait :active would be missing on :vip (entity :user) after the plan: " <>
                   "command :update_user removes it",
                 fn ->
                   produce(context, user: [:active, :premium, as: :vip])
                 end
  end

  test "a condition on an instance the plan creates is judged right before its command",
       context do
    assert_raise SeedFactory.MissingRequestedTraitError,
                 "requested trait :active would be missing on :member after the plan: " <>
                   "command :promote_member removes it",
                 fn ->
                   produce(context, member: [:active, :noted])
                 end
  end

  test "a declaration that never fires on the created instance is refused before its command",
       context do
    assert_raise SeedFactory.MissingRequestedTraitError,
                 "requested trait :platinum would be missing on :member after the plan: " <>
                   "no planned command applies it",
                 fn ->
                   produce(context, member: [:platinum])
                 end
  end

  test "a creation declaration that never fires is refused before its command", context do
    assert_raise SeedFactory.MissingRequestedTraitError,
                 "requested trait :legend would be missing on :member after the plan: " <>
                   "no planned command applies it",
                 fn ->
                   produce(context, member: [:legend])
                 end
  end

  test "an instance updated earlier in the plan is unknown to the prediction", context do
    context = exec(context, :create_member)

    # :demote_member runs first and lowers the tier, so :gold_only never
    # fires; a prediction trusting the pre-plan instance would refuse this.
    context = produce(context, member: [:active, :demoted, :reconsidered])

    assert :active in context.__seed_factory_meta__.current_traits.member
    assert context.member == %{tier: :gold}
  end

  test "a re-add through a pattern match on a created instance is judged once the card exists",
       context do
    # :stamped removes :fresh for sure; the card's level re-adds it, and the
    # pattern match would answer false on an unknown value.
    context = produce(context, card: [:fresh, :noted_card])

    current = context.__seed_factory_meta__.current_traits.card
    assert :fresh in current
    assert :stamped in current
  end

  test "only the requested traits are checked", context do
    context = exec(context, :create_user)
    context = produce(context, user: [:premium])

    assert context.__seed_factory_meta__.current_traits.user == [:premium, :blocked]
  end
end
