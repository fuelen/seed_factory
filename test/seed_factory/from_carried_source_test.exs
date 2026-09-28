defmodule SeedFactory.FromCarriedSourceTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    command :create_resolved_ticket do
      resolve(fn _ -> {:ok, %{ticket: %{state: :resolved}}} end)
      produce :ticket
    end

    command :reopen_ticket do
      param :ticket, entity: :ticket

      resolve(fn args ->
        send(self(), :reopened)
        {:ok, %{ticket: %{args.ticket | state: :open}}}
      end)

      update :ticket
    end

    command :close_ticket do
      param :ticket, entity: :ticket
      resolve(fn args -> {:ok, %{ticket: %{args.ticket | state: :closed}}} end)
      update :ticket
    end

    trait :resolved, :ticket do
      exec :create_resolved_ticket
    end

    trait :open, :ticket do
      from :resolved
      exec :reopen_ticket
    end

    trait :closed, :ticket do
      from [:open, :resolved]
      exec :close_ticket
    end
  end

  use SeedFactory.Test, schema: Schema
  import TraitAssertions

  test "a listed source the entity carries wins over one a command could bring back", context do
    context = context |> produce(ticket: [:resolved]) |> produce(ticket: [:closed])

    assert context.ticket.state == :closed
    assert_trait(context, :ticket, [:closed])
    refute_received :reopened
  end
end
