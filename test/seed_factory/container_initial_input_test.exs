defmodule SeedFactory.ContainerInitialInputTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Pre-existing quirk (v0.8.2 behaved identically).
    # Planning used to check initial_input coverage against the FLAT param
    # key while Params.prepare_args reads the nested value from
    # initial_input[container_key][nested_key]. An entity param supplied
    # inside a container was therefore still planned as a dependency: the
    # command producing it executed even though its value was never used.
    command :make_a do
      resolve(fn _ -> {:ok, %{a: :generated_a}} end)

      produce :a
    end

    command :use_wrapped do
      param :wrap do
        param :a, entity: :a
      end

      resolve(fn args -> {:ok, %{r: args.wrap.a}} end)

      produce :r
    end
  end

  use SeedFactory.Test, schema: Schema

  test "an entity param covered through a container is not planned", context do
    context = exec(context, :use_wrapped, wrap: %{a: :manual_a})

    assert context.r == :manual_a
    refute Map.has_key?(context, :a)
  end

  test "the nested input may be a keyword list, as prepare_args accepts one", context do
    context = exec(context, :use_wrapped, wrap: [a: :manual_a])

    assert context.r == :manual_a
    refute Map.has_key?(context, :a)
  end
end
