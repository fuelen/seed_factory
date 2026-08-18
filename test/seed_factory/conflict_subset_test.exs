defmodule SeedFactory.ConflictSubsetTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    defp gen_id, do: :erlang.unique_integer([:positive])

    # Requesting :prize registers the group [direct_award, earn_prize], then
    # award's group [grant_award, nominate_award, direct_award] and nomination's
    # group [grant_award, nominate_award], which is a subset of award's. The diff
    # of the two is [direct_award], and it must survive because it is still
    # a member of the prize group.
    command :grant_award do
      resolve(fn _ ->
        {:ok, %{award: %{id: gen_id()}, nomination: %{id: gen_id()}}}
      end)

      produce :award
      produce :nomination
    end

    command :nominate_award do
      resolve(fn _ ->
        {:ok, %{award: %{id: gen_id()}, nomination: %{id: gen_id()}}}
      end)

      produce :award
      produce :nomination
    end

    command :create_ceremony do
      param :_award, entity: :award

      resolve(fn _ ->
        {:ok, %{ceremony: %{id: gen_id()}}}
      end)

      produce :ceremony
    end

    command :direct_award do
      param :_ceremony, entity: :ceremony

      resolve(fn _ ->
        {:ok, %{award: %{id: gen_id()}, prize: %{id: gen_id()}}}
      end)

      produce :award
      produce :prize
    end

    command :earn_prize do
      param :_nomination, entity: :nomination

      resolve(fn _ ->
        {:ok, %{prize: %{id: gen_id()}}}
      end)

      produce :prize
    end

    trait :default, :ceremony do
      exec :create_ceremony
    end

    trait :direct, :prize do
      exec :direct_award
    end

    trait :earned, :prize do
      exec :earn_prize
    end
  end

  use SeedFactory.Test, schema: Schema

  test "is_subset conflict resolution preserves commands needed by other branches", context do
    context = produce(context, [:prize])

    assert context.prize
  end
end
