defmodule SeedFactory.FromConsumedSourceTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    command :create_doc do
      resolve(fn _ -> {:ok, %{doc: :doc}} end)
      produce :doc
    end

    command :flag_doc do
      param :doc, entity: :doc

      resolve(fn args ->
        send(self(), :flagged)
        {:ok, %{doc: args.doc}}
      end)

      update :doc
    end

    command :unflag_doc do
      param :doc, entity: :doc
      resolve(fn args -> {:ok, %{doc: args.doc}} end)
      update :doc
    end

    command :archive_doc do
      param :doc, entity: :doc
      resolve(fn args -> {:ok, %{doc: args.doc}} end)
      update :doc
    end

    trait :draft, :doc do
      exec :create_doc
    end

    trait :flagged, :doc do
      exec :flag_doc
    end

    trait :reviewed, :doc do
      from :draft
      exec :flag_doc
    end

    trait :unflagged, :doc do
      from :flagged
      exec :unflag_doc
    end

    trait :archived, :doc do
      from :flagged
      exec :archive_doc
    end
  end

  use SeedFactory.Test, schema: Schema
  import TraitAssertions

  test "a replaced source is not brought back by running its command again", context do
    context = produce(context, doc: [:unflagged])
    assert_receive :flagged

    assert_raise SeedFactory.TraitRemovedByCommandError,
                 ~r/cannot apply traits \[:flagged\] to :doc because they were removed by command :unflag_doc/,
                 fn -> produce(context, doc: [:archived]) end

    refute_received :flagged
    assert_trait(context, :doc, [:reviewed, :unflagged])
  end
end
