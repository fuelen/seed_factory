defmodule SeedFactory.DeleterPlanChoiceTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :make_everything alone satisfies the request. The resolution commits to
    # :make_draft_note for :draft first, which excludes :make_everything, so
    # :snapshot falls to the deleter and the requested :draft is consumed on
    # the way. v0.8.2 planned :make_everything.
    command :make_draft_note do
      resolve(fn _ -> {:ok, %{draft: {:dn, :draft}, note: {:dn, :note}}} end)

      produce :draft
      produce :note
    end

    command :make_everything do
      resolve(fn _ ->
        {:ok, %{draft: {:all, :draft}, note: {:all, :note}, snapshot: {:all, :snapshot}}}
      end)

      produce :draft
      produce :note
      produce :snapshot
    end

    command :make_note do
      resolve(fn _ -> {:ok, %{note: {:n, :note}}} end)

      produce :note
    end

    command :snapshot_draft do
      param :draft, entity: :draft

      resolve(fn _ -> {:ok, %{snapshot: {:sd, :snapshot}}} end)

      produce :snapshot
      delete :draft
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a plan without the deleter is preferred when it satisfies the request", context do
    context = produce(context, [:draft, :note, :snapshot])

    assert Map.has_key?(context, :draft)
    assert Map.has_key?(context, :note)
    assert Map.has_key?(context, :snapshot)
  end
end
