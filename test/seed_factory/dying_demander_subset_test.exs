defmodule SeedFactory.DyingDemanderSubsetTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # The narrowed demands of :from_beta and :from_delta point at subsets that
    # the resolution in favour of :make_rest wipes out — together with both
    # demanders. Treating those subsets as still protected used to reject
    # :make_rest and leave a mutually-requiring survivor pair, raising
    # CircularDependencyError on a request :make_rest alone satisfies.
    command :make_rest do
      resolve(fn _ ->
        {:ok, %{beta: {:rest, :beta}, gamma: {:rest, :gamma}, delta: {:rest, :delta}}}
      end)

      produce :beta
      produce :gamma
      produce :delta
    end

    command :from_beta do
      param :beta, entity: :beta

      resolve(fn _ -> {:ok, %{alpha: {:fb, :alpha}, delta: {:fb, :delta}}} end)

      produce :alpha
      produce :delta
    end

    command :from_delta do
      param :delta, entity: :delta

      resolve(fn _ -> {:ok, %{beta: {:fd, :beta}}} end)

      produce :beta
    end

    command :from_alpha_delta do
      param :alpha, entity: :alpha
      param :delta, entity: :delta

      resolve(fn _ -> {:ok, %{beta: {:fad, :beta}, gamma: {:fad, :gamma}}} end)

      produce :beta
      produce :gamma
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a subset dying with its demander does not block the resolution", context do
    context = produce(context, [:beta, :delta])

    assert Map.has_key?(context, :beta)
    assert Map.has_key?(context, :delta)
  end
end
