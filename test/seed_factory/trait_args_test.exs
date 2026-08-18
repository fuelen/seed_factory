defmodule SeedFactory.TraitArgsTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # One trait name is declared on several commands: :closed is reachable by
    # closing an open ticket and by an import that creates the ticket already closed.
    command :open_ticket do
      resolve(fn _ ->
        {:ok, %{ticket: %{status: :open, source: :web, external_id: nil}}}
      end)

      produce :ticket
    end

    command :import_ticket do
      param :status, value: :open
      param :external_id, value: "ext"

      resolve(fn args ->
        {:ok, %{ticket: %{status: args.status, source: :import, external_id: args.external_id}}}
      end)

      produce :ticket
    end

    command :close_ticket do
      param :ticket, entity: :ticket
      param :reason, value: :manual

      resolve(fn args ->
        {:ok, %{ticket: %{args.ticket | status: :closed}}}
      end)

      update :ticket
    end

    trait :imported, :ticket do
      exec :import_ticket
    end

    trait :closed, :ticket do
      exec :close_ticket, args_pattern: %{reason: :closing}
    end

    trait :closed, :ticket do
      exec :import_ticket do
        args_match(fn args -> args.status == :closed end)
        generate_args(fn -> %{status: :closed} end)
      end
    end
  end

  use SeedFactory.Test, schema: Schema

  import TraitAssertions

  test "produce applies only the args of the declaration whose command runs", context do
    context = produce(context, ticket: [:closed])

    assert context.ticket == %{status: :closed, source: :web, external_id: nil}
    assert_trait(context, :ticket, [:closed])
  end

  test "produce with a trait that forces another command uses that declaration's args",
       context do
    context = produce(context, ticket: [:imported, :closed])

    assert context.ticket == %{status: :closed, source: :import, external_id: "ext"}
    assert_trait(context, :ticket, [:imported, :closed])
  end
end
