defmodule SeedFactory.ParameterizedTraitMapConflictTest do
  use ExUnit.Case, async: true
  import SeedFactory

  defmodule Schema do
    use SeedFactory.Schema

    command :a_bad do
      param :payload
      param :flag

      resolve(fn args ->
        send(self(), :a_bad_ran)
        {:ok, %{item: args}}
      end)

      produce :item
    end

    command :z_good do
      param :payload
      param :flag
      resolve(fn args -> {:ok, %{item: args}} end)
      produce :item
    end

    trait :value, :item do
      exec :a_bad, args_pattern: %{payload: _}
    end

    trait :value, :item do
      exec :z_good, args_pattern: %{payload: _}
    end

    trait :special, :item do
      exec :a_bad, args_pattern: %{payload: %{b: 2}}
    end

    trait :special, :item do
      exec :z_good, args_pattern: %{flag: true}
    end

    trait :bad_only, :item do
      exec :a_bad, args_pattern: %{payload: %{b: 2}}
    end

    trait :nested, :item do
      exec :a_bad, args_pattern: %{payload: %{nested: _}}
    end

    trait :nested, :item do
      exec :z_good, args_pattern: %{payload: %{nested: _}}
    end

    trait :nested_special, :item do
      exec :a_bad, args_pattern: %{payload: %{nested: %{b: 2}}}
    end

    trait :nested_special, :item do
      exec :z_good, args_pattern: %{flag: true}
    end
  end

  test "search chooses the alternative that preserves the exact map" do
    for requests <- [
          [:special, value: %{a: 1}],
          [{:value, %{a: 1}}, :special],
          [:nested_special, nested: %{a: 1}],
          [{:nested, %{a: 1}}, :nested_special]
        ] do
      ctx = init(%{}, Schema) |> produce(item: requests)
      assert hd(ctx.__seed_factory_meta__.execution_history).commands == [:z_good]
      assert ctx.item.payload in [%{a: 1}, %{nested: %{a: 1}}]
      refute_received :a_bad_ran
    end
  end

  test "a partial map compatible with the whole value is still allowed" do
    for requests <- [[:bad_only, value: %{a: 1, b: 2}], [{:value, %{a: 1, b: 2}}, :bad_only]] do
      ctx = init(%{}, Schema) |> produce(item: requests)
      assert ctx.item.payload == %{a: 1, b: 2}
      assert {:value, %{a: 1, b: 2}} in ctx.__seed_factory_meta__.current_traits.item
      assert_received :a_bad_ran
    end
  end

  test "incompatible exact maps are rejected during search without executing commands" do
    assert_raise SeedFactory.TraitResolutionError, fn ->
      init(%{}, Schema) |> produce(item: [:bad_only, value: %{a: 1}])
    end

    refute_received :a_bad_ran
  end
end
