defmodule SeedFactory.RestrictedAlternativeTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :active is declared on two commands, so :create_p sits in a conflict
    # group when :use_e1 demands :e. The full candidate list then registers
    # :import_e, whose own demand (:archived x) conflicts with the requested
    # [:active] restriction.
    command :create_p do
      resolve(fn _ -> {:ok, %{x: :x_p, e: :e_p}} end)

      produce :x
      produce :e
    end

    command :create_p2 do
      resolve(fn _ -> {:ok, %{x: :x_p2}} end)

      produce :x
    end

    command :import_e do
      param :x, entity: :x, with_traits: [:archived]

      resolve(fn _ -> {:ok, %{e: :e_imported}} end)

      produce :e
    end

    command :archive_x do
      param :x, entity: :x

      resolve(fn _ -> {:ok, %{x: :x_archived}} end)

      update :x
    end

    command :use_e1 do
      param :e, entity: :e

      resolve(fn args -> {:ok, %{r: {:r, args.e}}} end)

      produce :r
    end

    command :use_e2 do
      resolve(fn _ -> {:ok, %{r: :r_plain}} end)

      produce :r
    end

    trait :active, :x do
      exec :create_p
    end

    trait :active, :x do
      exec :create_p2
    end

    trait :archived, :x do
      from :active
      exec :archive_x
    end
  end

  use SeedFactory.Test, schema: Schema

  test "an unneeded restricted alternative does not fail the plan", context do
    context = produce(context, [{:x, [:active]}, :r])

    assert Map.has_key?(context, :x)
    assert Map.has_key?(context, :r)
  end
end
