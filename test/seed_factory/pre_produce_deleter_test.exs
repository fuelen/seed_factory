defmodule SeedFactory.PreProduceDeleterTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :seal_document stays in the pre_produce plan as a dependency of
    # :frame_document while the explicitly requested consumers of :draft are
    # dropped from it.
    command :create_draft do
      resolve(fn _ -> {:ok, %{draft: :draft}} end)

      produce :draft
    end

    command :seal_document do
      param :draft, entity: :draft

      resolve(fn _ -> {:ok, %{sealed_document: :sealed_document}} end)

      produce :sealed_document
      delete :draft
    end

    command :display_draft do
      param :draft, entity: :draft

      resolve(fn args -> {:ok, %{display: {:display, args.draft}}} end)

      produce :display
    end

    command :frame_document do
      param :sealed_document, entity: :sealed_document

      resolve(fn args -> {:ok, %{framed_document: {:framed, args.sealed_document}}} end)

      produce :framed_document
    end
  end

  use SeedFactory.Test, schema: Schema

  test "produce orders the deleting command after its siblings", context do
    context = produce(context, [:framed_document, :display])

    assert context.display == {:display, :draft}
    assert context.framed_document == {:framed, :sealed_document}
  end

  test "pre_produce prepares dependencies when one of them deletes an entity", context do
    context = pre_produce(context, [:framed_document, :display])

    assert context.sealed_document == :sealed_document
    refute Map.has_key?(context, :framed_document)
    refute Map.has_key?(context, :display)
  end
end
