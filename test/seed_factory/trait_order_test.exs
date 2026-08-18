defmodule SeedFactory.TraitOrderTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :suspended chains to :reviewed via `from`, and both are also declared on
    # :import_license, so resolving [:suspended, :imported] registers conflict
    # groups before :imported arrives.
    command :issue_license do
      resolve(fn _ ->
        {:ok, %{license: %{source: :own, status: :active, reviewed: false}}}
      end)

      produce :license
    end

    command :import_license do
      param :status, value: :active

      resolve(fn args ->
        {:ok, %{license: %{source: :imported, status: args.status, reviewed: true}}}
      end)

      produce :license
    end

    command :review_license do
      param :license, entity: :license

      resolve(fn args ->
        {:ok, %{license: %{args.license | reviewed: true}}}
      end)

      update :license
    end

    command :suspend_license do
      param :license, entity: :license

      resolve(fn args ->
        {:ok, %{license: %{args.license | status: :suspended}}}
      end)

      update :license
    end

    trait :issued, :license do
      exec :issue_license
    end

    trait :imported, :license do
      exec :import_license
    end

    trait :reviewed, :license do
      exec :review_license
    end

    trait :reviewed, :license do
      exec :import_license
    end

    trait :suspended, :license do
      from :reviewed
      exec :suspend_license
    end

    trait :suspended, :license do
      exec :import_license, args_pattern: %{status: :suspended}
    end
  end

  use SeedFactory.Test, schema: Schema

  test "produce(license: [:suspended, :imported]) gives same result as produce(license: [:imported, :suspended])",
       context do
    context1 = produce(context, license: [:suspended, :imported])
    context2 = produce(context, license: [:imported, :suspended])

    assert context1.license == %{source: :imported, status: :suspended, reviewed: true}
    assert context2.license == context1.license

    assert context1.__seed_factory_meta__.current_traits[:license] ==
             context2.__seed_factory_meta__.current_traits[:license]
  end

  test "produce raises when requested traits force conflicting commands", context do
    error =
      assert_raise SeedFactory.TraitResolutionError, fn ->
        produce(context, license: [:suspended, :imported, :issued])
      end

    assert error.entity == :license
    assert error.trait == :imported

    assert_raise SeedFactory.TraitResolutionError, fn ->
      produce(context, license: [:issued, :imported, :suspended])
    end
  end
end
