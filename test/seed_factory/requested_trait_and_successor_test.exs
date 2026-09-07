defmodule SeedFactory.RequestedTraitAndSuccessorTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :t2 replaces :t1, so a request asking for both contradicts itself. The
    # restriction check refuses it for the request itself, not on behalf of a
    # command.
    command :make_e do
      resolve(fn _ -> {:ok, %{e: :e1}} end)

      produce :e
    end

    command :bump_e do
      param :e, entity: :e

      resolve(fn _ -> {:ok, %{e: :e2}} end)

      update :e
    end

    trait :t1, :e do
      exec :make_e
    end

    trait :t2, :e do
      from :t1
      exec :bump_e
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a request for a trait and its successor is refused with the request named", context do
    assert_raise SeedFactory.TraitRestrictionConflictError,
                 "cannot apply traits [:t2] to :e, requested with the traits [:t1, :t2]: " <>
                   "applying them would replace a requested trait",
                 fn ->
                   produce(context, e: [:t1, :t2])
                 end
  end
end
