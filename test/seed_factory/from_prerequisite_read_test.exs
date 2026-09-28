defmodule SeedFactory.FromPrerequisiteReadTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    command :create_user do
      resolve(fn _ -> {:ok, %{user: %{state: :pending}}} end)
      produce :user
    end

    command :approve_user do
      param :user, entity: :user
      resolve(fn args -> {:ok, %{user: %{args.user | state: :approved}}} end)
      update :user
    end

    command :reject_user do
      param :user, entity: :user
      resolve(fn args -> {:ok, %{user: %{args.user | state: :rejected}}} end)
      update :user
    end

    command :review_user do
      param :user, entity: :user
      resolve(fn args -> {:ok, %{user: %{args.user | state: :reviewed}}} end)
      update :user
    end

    command :archive_user do
      param :user, entity: :user
      resolve(fn args -> {:ok, %{user: %{args.user | state: :archived}}} end)
      update :user
    end

    command :create_report do
      param :user, entity: :user, with_traits: [:reviewed]
      resolve(fn _ -> {:ok, %{report: :report}} end)
      produce :report
    end

    command :create_audit do
      param :user, entity: :user
      param :mode, generate: fn -> :close end
      resolve(fn args -> {:ok, %{user: args.user, audit: :audit}} end)
      update :user
      produce :audit
    end

    command :score_user do
      param :user, entity: :user
      param :score, value: 0
      resolve(fn args -> {:ok, %{user: Map.put(args.user, :score, args.score)}} end)
      update :user
    end

    command :appeal_user do
      param :user, entity: :user
      resolve(fn args -> {:ok, %{user: %{args.user | state: :appealed}}} end)
      update :user
    end

    command :purge_user do
      param :user, entity: :user
      resolve(fn args -> {:ok, %{user: %{args.user | state: :purged}}} end)
      update :user
    end

    command :decline_user do
      param :user, entity: :user
      param :audit, entity: :audit
      resolve(fn args -> {:ok, %{user: %{args.user | state: :declined}}} end)
      update :user
    end

    trait :pending, :user do
      exec :create_user
    end

    trait :approved, :user do
      from :pending
      exec :approve_user
    end

    trait :rejected, :user do
      from :pending
      exec :reject_user
    end

    trait :reviewed, :user do
      from :pending
      exec :review_user
    end

    trait :archived, :user do
      from [:pending, :reviewed, :approved]
      exec :archive_user
    end

    trait :closed, :user do
      from :pending
      exec :create_audit, args_pattern: %{mode: :close}
    end

    trait :declined, :user do
      from :pending
      exec :decline_user
    end

    trait :appealed, :user do
      from :rejected
      exec :appeal_user
    end

    trait :purged, :user do
      from [:pending, :rejected]
      exec :purge_user
    end

    trait :score, :user do
      from :pending
      exec :score_user, args_pattern: %{score: _}
    end
  end

  use SeedFactory.Test, schema: Schema
  import TraitAssertions

  test "two transitions out of one trait in one request", context do
    assert_raise SeedFactory.TraitResolutionError,
                 ~r/applies :\w+ and removes :pending/,
                 fn -> produce(context, user: [:approved, :rejected]) end
  end

  test "a transition out of a trait an earlier request replaced", context do
    context = produce(context, user: [:approved])

    assert_raise SeedFactory.TraitRemovedByCommandError,
                 ~r/cannot apply traits \[:pending\] to :user because they were removed by command :approve_user/,
                 fn -> produce(context, user: [:rejected]) end

    assert_trait(context, :user, [:approved])
  end

  test "a parameter asking for a transition out of a replaced trait", context do
    context = produce(context, user: [:approved])

    for build <- [&exec(&1, :create_report), &pre_produce(&1, report: [])] do
      assert_raise SeedFactory.TraitRemovedByCommandError,
                   ~r/removed by command :approve_user/,
                   fn -> build.(context) end
    end
  end

  test "a transition out of the trait the entity carries", context do
    context = context |> produce(user: [:pending]) |> produce(user: [:rejected])

    assert context.user.state == :rejected
    assert_trait(context, :user, [:rejected])
  end

  test "a transition out of any listed trait uses the one the entity carries", context do
    context = context |> produce(user: [:approved]) |> produce(user: [:archived])

    assert context.user.state == :archived
    assert_trait(context, :user, [:archived])
  end

  test "a transition out of any listed trait takes the source the plan keeps", context do
    context = produce(context, user: [:archived], report: [])

    assert context.user.state == :archived
    assert_trait(context, :user, [:archived])
  end

  test "no listed source is carried or can be brought back", context do
    context = produce(context, user: [:rejected])

    assert_raise SeedFactory.TraitRemovedByCommandError,
                 ~r/cannot apply traits \[:pending\] to :user because they were removed by command :reject_user/,
                 fn -> produce(context, user: [:archived]) end
  end

  test "every listed source was replaced", context do
    context = produce(context, user: [:appealed])

    assert_raise SeedFactory.TraitRemovedByCommandError,
                 ~r/cannot apply traits \[:pending\] to :user because they were removed by command :reject_user/,
                 fn -> produce(context, user: [:purged]) end
  end

  test "a new value of a parameterized transition needs no source again", context do
    context = context |> produce(user: [score: 1]) |> produce(user: [score: 2])

    assert context.user.score == 2
    assert_trait(context, :user, score: 2)
  end

  test "a source trait lost to generated args fails before the first step", context do
    assert_raise SeedFactory.MissingRequestedTraitError,
                 ~r/trait :pending required by :decline_user would be missing on :user/,
                 fn -> produce(context, user: [:declined]) end

    refute Map.has_key?(context, :user)
  end
end
