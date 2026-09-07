defmodule SeedFactory.GeneratedArgsReuseTest do
  # The counter is a named process shared with the schema functions.
  use ExUnit.Case, async: false

  @counter :seed_factory_generated_args_reuse_counter

  defmodule Schema do
    use SeedFactory.Schema

    # The plan fixes the args of every step before anything runs: the
    # generators run once and the execution reuses their values. Both the
    # generated args of a declaration and a generate param count.
    command :create_e do
      resolve(fn _ -> {:ok, %{e: :e1}} end)

      produce :e
    end

    command :tag_e do
      param :e, entity: :e
      param :n, value: 0

      param :g,
        generate: fn ->
          Agent.get_and_update(SeedFactory.GeneratedArgsReuseTest.counter(), &{&1, &1 + 1})
        end

      resolve(fn args -> {:ok, %{e: {args.n, args.g}}} end)

      update :e
    end

    trait :tagged, :e do
      exec :tag_e,
        args_match: fn args -> is_integer(args.n) end,
        generate_args: fn ->
          %{n: Agent.get_and_update(SeedFactory.GeneratedArgsReuseTest.counter(), &{&1, &1 + 1})}
        end
    end
  end

  def counter, do: @counter

  use SeedFactory.Test, schema: Schema

  setup do
    {:ok, _pid} = Agent.start_link(fn -> 1 end, name: @counter)
    :ok
  end

  test "generators run once and the execution reuses their values", context do
    context = produce(context, e: [:tagged])

    assert context.e == {1, 2}
    assert Agent.get(@counter, & &1) == 3
  end
end
