defmodule SeedFactory.ExpiredDemanderTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Processing the first :marked declaration resolves conflicts in a way
    # that removes :refine_one before its own with_traits demand registers.
    # The registration must treat the demand as expired instead of linking to
    # the dead demander.
    command :make_gamma do
      resolve(fn _ -> {:ok, %{gamma: {:make_gamma, :gamma}}} end)

      produce :gamma
    end

    command :make_all do
      resolve(fn _ ->
        {:ok, %{alpha: {:make_all, :alpha}, beta: {:make_all, :beta}, gamma: {:make_all, :gamma}}}
      end)

      produce :alpha
      produce :beta
      produce :gamma
    end

    command :derive_beta do
      param :alpha, entity: :alpha, with_traits: [:marked]

      resolve(fn _ -> {:ok, %{beta: {:derive_beta, :beta}}} end)

      produce :beta
    end

    command :consume_gamma do
      param :gamma, entity: :gamma

      resolve(fn _ ->
        {:ok, %{alpha: {:consume_gamma, :alpha}, beta: {:consume_gamma, :beta}}}
      end)

      produce :alpha
      produce :beta
    end

    command :refine_one do
      param :alpha, entity: :alpha, with_traits: [:marked]

      resolve(fn _ -> {:ok, %{alpha: {:refine_one, :alpha}}} end)

      update :alpha
    end

    trait :marked, :alpha do
      exec :refine_one
    end

    trait :marked, :alpha do
      exec :make_all
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a demand of an already removed demander expires quietly", context do
    context = produce(context, [:alpha, :beta, :gamma])

    assert Map.has_key?(context, :alpha)
    assert Map.has_key?(context, :beta)
    assert Map.has_key?(context, :gamma)
  end
end
