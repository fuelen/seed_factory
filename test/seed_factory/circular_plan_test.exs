defmodule SeedFactory.CircularPlanTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # The trait-selected producers require each other's entities, so the execution
    # plan cannot be ordered.
    command :print_badge do
      resolve(fn _ ->
        {:ok, %{badge: "printed badge"}}
      end)

      produce :badge
    end

    command :issue_badge_for_pass do
      param :pass, entity: :pass

      resolve(fn args ->
        {:ok, %{badge: "badge for #{args.pass}"}}
      end)

      produce :badge
    end

    command :print_pass do
      resolve(fn _ ->
        {:ok, %{pass: "printed pass"}}
      end)

      produce :pass
    end

    command :issue_pass_for_badge do
      param :badge, entity: :badge

      resolve(fn args ->
        {:ok, %{pass: "pass for #{args.badge}"}}
      end)

      produce :pass
    end

    trait :issued_for_pass, :badge do
      exec :issue_badge_for_pass
    end

    trait :issued_for_badge, :pass do
      exec :issue_pass_for_badge
    end
  end

  use SeedFactory.Test, schema: Schema

  test "produce raises when selected commands form a circular dependency", context do
    assert_raise SeedFactory.CircularDependencyError,
                 "commands have circular dependencies: [:issue_badge_for_pass, :issue_pass_for_badge]",
                 fn ->
                   produce(context, badge: [:issued_for_pass], pass: [:issued_for_badge])
                 end
  end
end
