defmodule SeedFactory.SharedProducerAlternativeTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :a on e comes from :joint or :alternative, :b on f only from :joint, and
    # both commands also produce x. Whether x is produced twice depends on
    # the commands the plan picks, and one :joint serves both traits.
    command :joint do
      resolve(fn _ -> {:ok, %{e: :joint_e, f: :joint_f, x: :joint_x}} end)

      produce :e
      produce :f
      produce :x
    end

    command :alternative do
      resolve(fn _ -> {:ok, %{e: :alt_e, x: :alt_x}} end)

      produce :e
      produce :x
    end

    trait :a, :e do
      exec :joint
    end

    trait :a, :e do
      exec :alternative
    end

    trait :b, :f do
      exec :joint
    end
  end

  use SeedFactory.Test, schema: Schema

  test "an unused alternative producer of a side entity is no conflict", context do
    context = produce(context, e: [:a], f: [:b])

    assert context == Map.merge(context, %{e: :joint_e, f: :joint_f, x: :joint_x})
  end
end
