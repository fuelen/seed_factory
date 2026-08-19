defmodule SeedFactory.RemovedTraitDependencyTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :audit_ticket demands a :closed ticket via with_traits. A ticket that went
    # through :closed and lost it must not satisfy the demand.
    command :open_ticket do
      resolve(fn _ -> {:ok, %{ticket: :open_ticket}} end)

      produce :ticket
    end

    command :close_ticket do
      param :ticket, entity: :ticket

      resolve(fn _ -> {:ok, %{ticket: :closed_ticket}} end)

      update :ticket
    end

    command :reopen_ticket do
      param :ticket, entity: :ticket

      resolve(fn _ -> {:ok, %{ticket: :reopened_ticket}} end)

      update :ticket
    end

    command :audit_ticket do
      param :ticket, entity: :ticket, with_traits: [:closed]

      resolve(fn args -> {:ok, %{audit: {:audit_of, args.ticket}}} end)

      produce :audit
    end

    # :review has an alternative producer without demands, so a dead demand of
    # :review_closed_ticket must drop it from the conflict group instead of
    # failing the whole plan.
    command :review_closed_ticket do
      param :ticket, entity: :ticket, with_traits: [:closed]

      resolve(fn args -> {:ok, %{review: {:review_closed, args.ticket}}} end)

      produce :review
    end

    command :review_any_ticket do
      param :ticket, entity: :ticket

      resolve(fn args -> {:ok, %{review: {:review_any, args.ticket}}} end)

      produce :review
    end

    trait :open, :ticket do
      exec :open_ticket
    end

    trait :closed, :ticket do
      from :open
      exec :close_ticket
    end

    trait :reopened, :ticket do
      from :closed
      exec :reopen_ticket
    end
  end

  use SeedFactory.Test, schema: Schema

  test "produce raises when a dependency lost the demanded trait", context do
    context =
      context
      |> produce(:ticket)
      |> exec(:close_ticket)
      |> exec(:reopen_ticket)

    assert_raise SeedFactory.TraitRemovedByCommandError, fn ->
      produce(context, :audit)
    end
  end

  test "exec raises when a dependency lost the demanded trait", context do
    context =
      context
      |> produce(:ticket)
      |> exec(:close_ticket)
      |> exec(:reopen_ticket)

    assert_raise SeedFactory.TraitRemovedByCommandError, fn ->
      exec(context, :audit_ticket)
    end
  end

  test "a currently closed ticket satisfies the demand", context do
    context =
      context
      |> produce(:ticket)
      |> exec(:close_ticket)
      |> produce(:audit)

    assert context.audit == {:audit_of, :closed_ticket}
  end

  test "a candidate with a dead demand loses to another producer", context do
    context =
      context
      |> produce(:ticket)
      |> exec(:close_ticket)
      |> exec(:reopen_ticket)
      |> produce(:review)

    assert context.review == {:review_any, :reopened_ticket}
  end

  test "the demanding candidate wins while the trait is present", context do
    context =
      context
      |> produce(:ticket)
      |> exec(:close_ticket)
      |> produce(:review)

    assert context.review == {:review_closed, :closed_ticket}
  end
end
