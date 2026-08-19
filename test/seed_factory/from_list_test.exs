defmodule SeedFactory.FromListTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :approved consumes :draft through a from-list. Requesting an already
    # consumed trait must fail the same way as with a single-atom from.
    command :create_document do
      resolve(fn _ -> {:ok, %{document: :new_document}} end)

      produce :document
    end

    command :review_document do
      param :document, entity: :document

      resolve(fn _ -> {:ok, %{document: :reviewed_document}} end)

      update :document
    end

    command :approve_document do
      param :document, entity: :document

      resolve(fn _ -> {:ok, %{document: :approved_document}} end)

      update :document
    end

    trait :draft, :document do
      exec :create_document
    end

    trait :reviewed, :document do
      from :draft
      exec :review_document
    end

    trait :approved, :document do
      from [:draft, :reviewed]
      exec :approve_document
    end
  end

  use SeedFactory.Test, schema: Schema

  test "requesting a trait consumed by a from-list transition raises", context do
    context =
      context
      |> produce(:document)
      |> exec(:approve_document)

    assert_raise SeedFactory.TraitRemovedByCommandError, fn ->
      produce(context, document: [:draft])
    end
  end
end
