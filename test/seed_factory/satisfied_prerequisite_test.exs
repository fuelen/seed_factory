defmodule SeedFactory.SatisfiedPrerequisiteTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :stamped is declared on both commands and both of them sit in the trail:
    # :import_doc executed without matching the args pattern, :stamp_doc added
    # the trait. The declaration order must not decide which trail entry is
    # consulted.
    command :import_doc do
      param :stamped, value: false

      resolve(fn _ -> {:ok, %{doc: :imported_doc}} end)

      produce :doc
    end

    command :stamp_doc do
      param :doc, entity: :doc
      param :hard, value: true

      resolve(fn _ -> {:ok, %{doc: :stamped_doc}} end)

      update :doc
    end

    command :seal_doc do
      param :doc, entity: :doc

      resolve(fn _ -> {:ok, %{doc: :sealed_doc}} end)

      update :doc
    end

    trait :stamped, :doc do
      exec :import_doc, args_pattern: %{stamped: true}
    end

    trait :stamped, :doc do
      exec :stamp_doc, args_pattern: %{hard: true}
    end

    trait :sealed, :doc do
      from :stamped
      exec :seal_doc
    end
  end

  use SeedFactory.Test, schema: Schema
  import TraitAssertions

  test "a prerequisite satisfied by a later declaration is not a mismatch", context do
    # Was: TraitResolutionError claiming :stamped cannot be satisfied while the
    # entity currently had it.
    context =
      context
      |> exec(:import_doc, stamped: false)
      |> exec(:stamp_doc)
      |> produce(doc: [:sealed])

    assert context.doc == :sealed_doc
    assert_trait(context, :doc, [:sealed])
  end

  test "a mismatch reports every executed declaration", context do
    context =
      context
      |> exec(:import_doc, stamped: false)
      |> exec(:stamp_doc, hard: false)

    error =
      assert_raise SeedFactory.TraitResolutionError, fn ->
        produce(context, doc: [:sealed])
      end

    message = Exception.message(error)

    assert message =~ "traits of previously executed command :import_doc do not match"
    assert message =~ "traits of previously executed command :stamp_doc do not match"
  end
end
