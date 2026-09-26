defmodule SeedFactory.ParameterizedTraitsTest do
  use ExUnit.Case, async: true
  import SeedFactory

  defmodule Schema do
    use SeedFactory.Schema

    command :create_user do
      param :age, value: 30
      param :active, value: false

      param :address do
        param :country, value: "UA"
      end

      resolve(fn args -> {:ok, %{user: args}} end)
      produce :user
    end

    command :set_age do
      param :user, entity: :user
      param :age
      resolve(fn args -> {:ok, %{user: %{args.user | age: args.age}}} end)
      update :user
    end

    command :activate do
      param :user, entity: :user
      resolve(fn args -> {:ok, %{user: %{args.user | active: true}}} end)
      update :user
    end

    command :create_badge do
      param :user, entity: :user, with_traits: [:active, age: 18]
      resolve(fn args -> {:ok, %{badge: args.user}} end)
      produce :badge
    end

    trait :age, :user do
      exec :create_user, args_pattern: %{age: _}
    end

    trait :age, :user do
      exec :set_age do
        args_pattern(%{age: _})
      end
    end

    trait :country, :user do
      exec :create_user, args_pattern: %{address: %{country: _}}
    end

    trait :active, :user do
      exec :activate
    end
  end

  defp context, do: init(%{}, Schema)
  defp traits(ctx, entity \\ :user), do: ctx.__seed_factory_meta__.current_traits[entity]

  test "produce combines ordinary and parameterized traits, including nested maps" do
    ctx = produce(context(), user: [:active, age: 18, country: "PL"])
    assert ctx.user == %{age: 18, active: true, address: %{country: "PL"}}
    assert {:age, 18} in traits(ctx)
    assert {:country, "PL"} in traits(ctx)
    assert :active in traits(ctx)
  end

  test "direct exec extracts values even when no trait was requested" do
    ctx = exec(context(), :create_user, age: 21)
    assert {:age, 21} in traits(ctx)
    assert {:country, "UA"} in traits(ctx)
  end

  test "matching requests do not execute another command" do
    ctx = exec(context(), :create_user, age: 18)
    next = produce(ctx, user: [age: 18])
    assert next.user == ctx.user
    assert hd(next.__seed_factory_meta__.execution_history).commands == []
  end

  test "another requested value selects an updater and replaces the old value" do
    ctx = context() |> produce(user: [age: 18]) |> produce(user: [age: 21])
    assert ctx.user.age == 21
    assert {:age, 21} in traits(ctx)
    refute {:age, 18} in traits(ctx)
    assert hd(ctx.__seed_factory_meta__.execution_history).commands == [:set_age]
    assert {:country, "UA"} in traits(ctx)
  end

  test "direct updates replace values without duplicating identical values" do
    ctx =
      context() |> produce(user: [age: 18]) |> exec(:set_age, age: 21) |> exec(:set_age, age: 21)

    assert Enum.filter(traits(ctx), &match?({:age, _}, &1)) == [age: 21]

    assert ctx.__seed_factory_meta__.trails.user
           |> SeedFactory.Trail.to_list()
           |> Enum.filter(&match?({:set_age, _added, _removed}, &1)) == [
             {:set_age, [age: 21], [age: 18]},
             {:set_age, [age: 21], []}
           ]
  end

  test "parameter replacement preserves unrelated ordinary trait occurrences" do
    ctx =
      context()
      |> produce(user: [age: 18])
      |> exec(:activate)
      |> exec(:activate)
      |> exec(:set_age, age: 21)
      |> exec(:set_age, age: 21)

    assert ctx.user.age == 21
    assert Enum.count(traits(ctx), &(&1 == :active)) == 2
    assert Enum.filter(traits(ctx), &match?({:age, _}, &1)) == [age: 21]
    assert {:country, "UA"} in traits(ctx)
  end

  test "with_traits carries a value to dependencies" do
    ctx = produce(context(), :badge)
    assert ctx.badge.age == 18
    assert ctx.badge.active
  end

  test "pre_produce and pre_exec prepare dependencies with values" do
    ctx = pre_produce(context(), :badge)
    assert ctx.user.age == 18
    refute Map.has_key?(ctx, :badge)
    ctx = pre_exec(context(), :create_badge)
    assert ctx.user.age == 18
    refute Map.has_key?(ctx, :badge)
  end

  test "rebinding coexists with value arguments" do
    ctx = produce(context(), user: [:active, age: 18, as: :author])
    assert ctx.author.age == 18
    assert {:age, 18} in traits(ctx, :author)
    refute Map.has_key?(ctx, :user)
  end

  test "nil rebinding leaves parameterized requests at their default binding" do
    for operation <- [&produce/2, &pre_produce/2] do
      assert operation.(context(), user: [age: 18, as: nil]) ==
               operation.(context(), user: [age: 18])

      assert operation.(context(), user: nil, user: [age: 18]) ==
               operation.(context(), user: [age: 18])
    end
  end

  test "a nil binding does not conflict with a named one" do
    for {request, age} <- [
          {[user: nil, user: [age: 18, as: :author]], 18},
          {[user: [as: nil], user: :author], 30}
        ] do
      ctx = produce(context(), request)
      assert ctx.author.age == age
      refute Map.has_key?(ctx, :user)
    end
  end

  test "whole-map and numeric parameter values are tracked with exact equality" do
    for {before, after_value} <- [{%{years: 18}, %{years: 18, months: 2}}, {18, 18.0}] do
      ctx = context() |> produce(user: [age: before]) |> produce(user: [age: after_value])
      assert ctx.user.age === after_value
      assert {:age, after_value} in traits(ctx)
      refute {:age, before} in traits(ctx)
      assert hd(ctx.__seed_factory_meta__.execution_history).commands == [:set_age]
    end
  end

  test "nil, false, maps and tuples are ordinary trait values" do
    for value <- [nil, false, %{years: 18}, {:years, 18}] do
      ctx = produce(context(), user: [age: value])
      assert ctx.user.age === value
      assert {:age, value} in traits(ctx)
      assert produce(ctx, user: [age: value]).user == ctx.user
    end
  end

  test "a parameterized trait requires a value, ordinary traits reject values" do
    assert_raise ArgumentError, ~r/requires a value/, fn -> produce(context(), user: [:age]) end

    assert_raise ArgumentError, ~r/does not accept a value/, fn ->
      produce(context(), user: [active: true])
    end
  end

  test "conflicting values in the same request are rejected" do
    for {first, second} <- [{18, 21}, {18, 18.0}] do
      assert_raise ArgumentError,
                   "conflicting values for trait :age of entity :user: #{inspect([first, second])}",
                   fn -> produce(context(), user: [age: first, age: second]) end
    end
  end

  test "repeated entity entries merge traits before validation and planning" do
    ctx = produce(context(), [:user, user: [:active], user: [age: 18], user: [age: 18]])
    assert ctx.user.age == 18
    assert ctx.user.active
    assert Enum.count(traits(ctx), &(&1 == {:age, 18})) == 1

    assert ctx.user == produce(context(), user: [:active, age: 18]).user
  end

  test "conflicting values across repeated entries are rejected at the boundary" do
    for operation <- [&produce/2, &pre_produce/2] do
      assert_raise ArgumentError, ~r/conflicting values for trait :age/, fn ->
        operation.(context(), user: [age: 18], user: [age: 21])
      end
    end
  end

  test "repeated entries share one binding and reject conflicting bindings" do
    ctx = produce(context(), user: :author, user: [:active, age: 18, as: :author])
    assert ctx.author.age == 18
    assert ctx.author.active
    refute Map.has_key?(ctx, :user)

    for operation <- [&produce/2, &pre_produce/2] do
      assert_raise ArgumentError,
                   "conflicting bindings for entity :user: :author and :reviewer",
                   fn ->
                     operation.(context(), user: :author, user: [age: 18, as: :reviewer])
                   end
    end
  end

  test "pre_produce validates requested references before planning too" do
    assert_raise ArgumentError, ~r/requires a value/, fn ->
      pre_produce(context(), user: [:age, as: :author])
    end

    assert_raise ArgumentError, ~r/conflicting values/, fn ->
      pre_produce(context(), user: [age: 18, age: 21])
    end

    assert_raise SeedFactory.UnknownTraitError, fn ->
      pre_produce(context(), user: [unknown: 18])
    end
  end

  test "duplicate as options in one entry are checked before planning" do
    for operation <- [&produce/2, &pre_produce/2] do
      assert_raise ArgumentError, ~r/conflicting bindings for entity :user/, fn ->
        operation.(context(), user: [age: 18, as: :author, as: :reviewer])
      end

      assert operation.(context(), user: [age: 18, as: :author, as: :author]) ==
               operation.(context(), user: [age: 18, as: :author])
    end
  end

  test "malformed trait references have an input error" do
    assert_raise ArgumentError, ~r/invalid trait reference/, fn ->
      produce(context(), user: [{:age, 18, :extra}])
    end
  end

  test "unknown parameterized traits have the normal diagnostic" do
    assert_raise SeedFactory.UnknownTraitError, ~r/doesn't have trait :ag/, fn ->
      produce(context(), user: [ag: 18])
    end
  end

  defmodule ConditionalSchema do
    use SeedFactory.Schema
    @percentage :percentage

    command :create_order do
      param :kind, value: :fixed
      param :amount, value: 10
      resolve(fn args -> {:ok, %{order: args}} end)
      produce :order
    end

    trait :discount, :order do
      exec :create_order, args_pattern: %{kind: @percentage, amount: _}
    end
  end

  test "fixed fields constrain extraction and generation" do
    ctx = init(%{}, ConditionalSchema)
    assert traits(exec(ctx, :create_order), :order) == []
    assert traits(exec(ctx, :create_order, kind: :percentage), :order) == [discount: 10]
    produced = produce(ctx, order: [discount: 15])
    assert produced.order == %{kind: :percentage, amount: 15}
    assert traits(produced, :order) == [discount: 15]
  end

  test "a property with no updater cannot silently change an existing value" do
    ctx = init(%{}, ConditionalSchema) |> produce(order: [discount: 15])

    assert_raise SeedFactory.TraitResolutionError, fn ->
      produce(ctx, order: [discount: 20])
    end
  end

  defmodule OrderingSchema do
    use SeedFactory.Schema

    command :create_user do
      param :age, value: 18

      resolve(fn args ->
        send(self(), {:created_user, args.age})
        {:ok, %{user: args.age}}
      end)

      produce :user
    end

    command :birthday do
      param :user, entity: :user
      param :age, value: 21
      resolve(fn args -> {:ok, %{user: args.age, birthday: true}} end)
      update :user
      produce :birthday
    end

    command :restore do
      param :user, entity: :user
      param :birthday, entity: :birthday
      param :age, value: 18
      resolve(fn args -> {:ok, %{user: args.age, restored: true}} end)
      update :user
      produce :restored
    end

    command :consume do
      param :user, entity: :user, with_traits: [age: 18]
      resolve(fn args -> {:ok, %{snapshot: args.user}} end)
      produce :snapshot
    end

    command :consume_after_birthday do
      param :user, entity: :user, with_traits: [age: 18]
      param :birthday, entity: :birthday
      resolve(fn args -> {:ok, %{late_snapshot: args.user}} end)
      produce :late_snapshot
    end

    trait :age, :user do
      exec :create_user, args_pattern: %{age: _}
    end

    trait :age, :user do
      exec :birthday, args_pattern: %{age: _}
    end

    trait :age, :user do
      exec :restore, args_pattern: %{age: _}
    end

    trait :twenty_one, :birthday do
      exec :birthday, args_pattern: %{age: 21}
    end
  end

  test "a consumer sees its value before a later overwrite" do
    ctx = init(%{}, OrderingSchema) |> produce([:snapshot, birthday: [:twenty_one]])
    assert ctx.snapshot == 18
    assert ctx.user == 21
    assert traits(ctx) == [age: 21]
  end

  test "a requested final value is restored after another command overwrites it" do
    ctx = init(%{}, OrderingSchema) |> produce(user: [age: 18], birthday: [:twenty_one])
    assert ctx.user == 18
    assert ctx.restored
    assert traits(ctx) == [age: 18]
  end

  test "an initially satisfied value can be restored if another request overwrites it" do
    ctx = init(%{}, OrderingSchema) |> produce(user: [age: 18])
    ctx = produce(ctx, user: [age: 18], birthday: [:twenty_one])
    assert ctx.user == 18
    assert ctx.restored
    assert traits(ctx) == [age: 18]
  end

  test "a dependency value is restored before a consumer after the overwrite" do
    ctx = init(%{}, OrderingSchema) |> produce([:late_snapshot, birthday: [:twenty_one]])
    assert ctx.late_snapshot == 18
    assert ctx.restored
  end

  defmodule IrreversibleOverwriteSchema do
    use SeedFactory.Schema

    command :create_user do
      param :age, value: 18
      resolve(fn args -> {:ok, %{user: args.age}} end)
      produce :user
    end

    command :birthday do
      param :user, entity: :user
      param :age, value: 21

      resolve(fn args ->
        send(self(), :irreversible_birthday_executed)
        {:ok, %{user: args.age, birthday: true}}
      end)

      update :user
      produce :birthday
    end

    trait :age, :user do
      exec :create_user, args_pattern: %{age: _}
    end

    trait :age, :user do
      exec :birthday, args_pattern: %{age: _}
    end

    trait :twenty_one, :birthday do
      exec :birthday, args_pattern: %{age: 21}
    end
  end

  test "an existing value cannot be kept when another request irreversibly overwrites it" do
    ctx = init(%{}, IrreversibleOverwriteSchema) |> produce(user: [age: 18])

    assert_raise SeedFactory.TraitResolutionError, fn ->
      produce(ctx, user: [age: 18], birthday: [:twenty_one])
    end

    refute_received :irreversible_birthday_executed
  end

  defmodule GeneratedOverwriteSchema do
    use SeedFactory.Schema

    command :create_user do
      param :age, value: 18

      resolve(fn args ->
        send(self(), :generated_schema_created_user)
        {:ok, %{user: args.age}}
      end)

      produce :user
    end

    command :birthday do
      param :user, entity: :user
      param :age, generate: fn -> 21 end
      resolve(fn args -> {:ok, %{user: args.age, birthday: true}} end)
      update :user
      produce :birthday
    end

    trait :age, :user do
      exec :create_user, args_pattern: %{age: _}
    end

    # The parameterized and generated declarations share the same argument.
    trait :age, :user do
      exec :birthday, args_pattern: %{age: _}
    end

    trait :changed, :birthday do
      exec :birthday,
        generate_args: fn -> %{age: 21} end,
        args_match: fn args -> args.age == 21 end
    end
  end

  test "generated overwrites are rejected before any command executes" do
    ctx = init(%{}, GeneratedOverwriteSchema)

    assert_raise SeedFactory.MissingRequestedTraitError, fn ->
      produce(ctx, user: [age: 18], birthday: [:changed])
    end

    refute_received :generated_schema_created_user
  end
end
