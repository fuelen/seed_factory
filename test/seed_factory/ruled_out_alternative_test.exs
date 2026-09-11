defmodule SeedFactory.RuledOutAlternativeTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :enroll, the first producer of :member, needs a :project. Besides
    # :plan_project, :project has a second producer, :import_project, which
    # needs an :office with :linked. An office made without :linked sits in
    # the context, so :import_project is ruled out before any decision is
    # taken. A dead alternative nobody would choose must not make :enroll
    # look unsafe and hand :member to :walk_in.
    command :make_office do
      param :api, value: :none

      resolve(fn args -> {:ok, %{office: %{api: args.api}}} end)

      produce :office
    end

    command :plan_project do
      param :office, entity: :office

      resolve(fn _ -> {:ok, %{project: :planned}} end)

      produce :project
    end

    command :import_project do
      param :office, entity: :office, with_traits: [:linked]

      resolve(fn _ -> {:ok, %{project: :imported}} end)

      produce :project
    end

    command :enroll do
      param :project, entity: :project
      param :tier, value: :regular

      resolve(fn args -> {:ok, %{member: {:enrolled, args.tier}}} end)

      produce :member
    end

    command :walk_in do
      param :tier, value: :regular

      resolve(fn args -> {:ok, %{member: {:walked_in, args.tier}}} end)

      produce :member
    end

    trait :linked, :office do
      exec :make_office, args_pattern: %{api: :linked}
    end

    trait :vip, :member do
      exec :enroll, args_pattern: %{tier: :vip}
    end

    trait :vip, :member do
      exec :walk_in, args_pattern: %{tier: :vip}
    end
  end

  use SeedFactory.Test, schema: Schema

  test "an alternative the context rules out does not change the producer", context do
    context = context |> exec(:make_office) |> produce(:member)

    assert context.member == {:enrolled, :regular}
    assert context.project == :planned
  end

  test "an alternative the context rules out does not change the trait declaration either",
       context do
    context = context |> exec(:make_office) |> produce(member: [:vip])

    assert context.member == {:enrolled, :vip}
    assert context.project == :planned
  end
end
