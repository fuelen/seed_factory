defmodule SeedFactory.SharedDeclarationGeneratorTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :make_a and :make_b both ask for a :tagged user, so the same declaration
    # reaches :make_user through two edges; its generator still runs once.
    # :stamped is a second declaration on the same command and keeps its own
    # generated args.
    command :make_user do
      param :id, value: 0
      param :stamp, value: nil

      resolve(fn args -> {:ok, %{user: {args.id, args.stamp}}} end)

      produce :user
    end

    command :make_a do
      param :user, entity: :user, with_traits: [:tagged]

      resolve(fn _ -> {:ok, %{a: :a1}} end)

      produce :a
    end

    command :make_b do
      param :user, entity: :user, with_traits: [:tagged]

      resolve(fn _ -> {:ok, %{b: :b1}} end)

      produce :b
    end

    trait :tagged, :user do
      exec :make_user,
        args_match: fn args -> is_integer(args.id) end,
        generate_args: fn ->
          send(self(), :generated_id)
          %{id: 7}
        end
    end

    trait :stamped, :user do
      exec :make_user,
        args_match: fn args -> args.stamp == :s end,
        generate_args: fn ->
          send(self(), :generated_stamp)
          %{stamp: :s}
        end
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a declaration shared by two consumers generates its args once", context do
    context = produce(context, [:a, :b])

    assert context.user == {7, nil}
    assert_received :generated_id
    refute_received :generated_id
  end

  test "two declarations on one command each generate their args", context do
    context = produce(context, [:a, :b, user: [:stamped]])

    assert context.user == {7, :s}
    assert_received :generated_id
    refute_received :generated_id
    assert_received :generated_stamp
    refute_received :generated_stamp
  end
end
