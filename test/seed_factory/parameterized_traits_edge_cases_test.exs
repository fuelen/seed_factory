defmodule SeedFactory.ParameterizedTraitsEdgeCasesTest do
  use ExUnit.Case, async: true
  import SeedFactory

  defmodule ConditionalSchema do
    use SeedFactory.Schema

    command :create do
      param :kind, value: :tracked
      param :payload, value: %{}
      resolve(fn args -> {:ok, %{item: args}} end)
      produce :item
    end

    command :change do
      param :item, entity: :item
      param :kind, value: :ignored
      param :payload, value: %{value: 21}

      resolve(fn args ->
        {:ok, %{item: %{kind: args.kind, payload: args.payload}, changed: true}}
      end)

      update :item
      produce :changed
    end

    trait :property, :item do
      exec :create, args_pattern: %{kind: :tracked, payload: %{value: _}}
    end

    trait :property, :item do
      exec :change, args_pattern: %{kind: :tracked, payload: %{value: _}}
    end

    trait :ignored, :changed do
      exec :change, args_pattern: %{kind: :ignored}
    end

    trait :empty, :changed do
      exec :change, args_pattern: %{kind: :tracked, payload: %{}}
    end

    trait :nil_payload, :changed do
      exec :change, args_pattern: %{kind: :tracked, payload: nil}
    end

    trait :scalar_payload, :changed do
      exec :change, args_pattern: %{kind: :tracked, payload: 18}
    end
  end

  test "direct execution extracts only present nested parameters" do
    for payload <- [%{}, nil, 18, []] do
      ctx = init(%{}, ConditionalSchema) |> exec(:create, payload: payload)
      assert ctx.item.payload == payload
      assert ctx.__seed_factory_meta__.current_traits.item == []
    end

    for value <- [nil, false, %{years: 18}] do
      ctx = init(%{}, ConditionalSchema) |> exec(:create, payload: %{value: value})
      assert ctx.__seed_factory_meta__.current_traits.item == [property: value]
    end
  end

  test "a fixed-field mismatch does not replace an existing parameterized trait" do
    ctx = init(%{}, ConditionalSchema) |> produce(item: [property: 18])
    ctx = produce(ctx, item: [property: 18], changed: [:ignored])
    assert ctx.changed
    assert ctx.item.kind == :ignored
    assert ctx.__seed_factory_meta__.current_traits.item == [property: 18]
  end

  test "updates with absent or non-map payloads preserve the last extracted value" do
    for requested <- [:empty, :nil_payload, :scalar_payload] do
      ctx = init(%{}, ConditionalSchema) |> produce(item: [property: nil])
      ctx = produce(ctx, item: [property: nil], changed: [requested])
      assert ctx.changed
      assert ctx.__seed_factory_meta__.current_traits.item == [property: nil]
    end
  end

  defmodule EntityPayloadSchema do
    use SeedFactory.Schema

    command :create_source do
      resolve(fn _ -> {:ok, %{source: %{value: 18}}} end)
      produce :source
    end

    command :create_item do
      param :payload, entity: :source
      resolve(fn args -> {:ok, %{item: args.payload}} end)
      produce :item
    end

    trait :property, :item do
      exec :create_item, args_pattern: %{payload: %{value: _}}
    end

    command :refresh do
      param :item, entity: :item
      param :payload, entity: :source
      param :changed_source, entity: :changed_source
      resolve(fn args -> {:ok, %{item: args.payload, refreshed: true}} end)
      update :item
      produce :refreshed
    end

    command :change_source do
      param :source, entity: :source
      resolve(fn _ -> {:ok, %{source: %{value: 18}, changed_source: true}} end)
      update :source
      produce :changed_source
    end

    trait :property, :item do
      exec :refresh, args_pattern: %{payload: %{value: _}}
    end

    trait :from_source, :refreshed do
      exec :refresh, generate_args: fn -> %{} end, args_match: fn _ -> true end
    end
  end

  test "a parameter nested inside a not-yet-produced entity is extracted after execution" do
    ctx = init(%{}, EntityPayloadSchema) |> produce(:item)
    assert ctx.item == %{value: 18}
    assert ctx.__seed_factory_meta__.current_traits.item == [property: 18]
  end

  test "a nested trait remains valid when its source is updated earlier in the plan" do
    ctx = init(%{}, EntityPayloadSchema) |> produce(:item)
    ctx = produce(ctx, item: [property: 18], refreshed: [:from_source])
    assert ctx.refreshed
    assert ctx.changed_source
    assert ctx.item == %{value: 18}

    assert Enum.reverse(hd(ctx.__seed_factory_meta__.execution_history).commands) ==
             [:change_source, :refresh]

    assert ctx.__seed_factory_meta__.current_traits.item == [property: 18]
  end

  defmodule ContainerSchema do
    use SeedFactory.Schema

    command :create do
      param :payload do
        param :years, value: 18
        param :months, generate: fn -> 2 end
      end

      resolve(fn args ->
        send(self(), :container_resolver_executed)
        {:ok, %{item: args.payload}}
      end)

      produce :item
    end

    trait :years, :item do
      exec :create, args_pattern: %{payload: %{years: _}}
    end

    trait :property, :item do
      exec :create, args_pattern: %{payload: _}
    end

    command :change do
      param :item, entity: :item

      param :payload do
        param :years, value: 18
        param :months, generate: fn -> 3 end
      end

      resolve(fn args ->
        send(self(), :container_change_executed)
        {:ok, %{item: args.payload, changed: true}}
      end)

      update :item
      produce :changed
    end

    trait :years, :item do
      exec :change, args_pattern: %{payload: %{years: _}}
    end

    trait :property, :item do
      exec :change, args_pattern: %{payload: _}
    end

    trait :generated, :changed do
      exec :change,
        generate_args: fn -> %{payload: %{years: 18, months: 3}} end,
        args_match: fn args -> args.payload == %{years: 18, months: 3} end
    end
  end

  test "whole-map requests reject missing generated fields before running resolvers" do
    assert_raise ArgumentError,
                 "trait :property of entity :item needs every nested key of param :payload, missing: :months",
                 fn -> init(%{}, ContainerSchema) |> produce(item: [property: %{years: 18}]) end

    refute_received :container_resolver_executed

    ctx = init(%{}, ContainerSchema) |> produce(item: [property: %{years: 18, months: 2}])
    assert ctx.item == %{years: 18, months: 2}

    assert ctx.__seed_factory_meta__.current_traits.item == [
             property: %{years: 18, months: 2},
             years: 18
           ]
  end

  test "a generated field in a whole-map update is checked before execution" do
    ctx = init(%{}, ContainerSchema) |> produce(:item)

    error =
      assert_raise SeedFactory.MissingRequestedTraitError, fn ->
        produce(ctx, item: [property: %{years: 18, months: 2}], changed: [:generated])
      end

    assert error.removed_when == :assigned
    assert error.assigned_value == %{years: 18, months: 3}

    assert Exception.message(error) ==
             "requested trait #{inspect({:property, %{years: 18, months: 2}})} would be missing on :item after the plan: " <>
               "command :change assigns #{inspect(error.assigned_value)} instead"

    refute_received :container_change_executed
  end

  defmodule RiderSchema do
    use SeedFactory.Schema

    command :create do
      param :payload, value: %{}

      resolve(fn args ->
        send(self(), :rider_resolver_executed)
        {:ok, %{item: args.payload}}
      end)

      produce :item
    end

    trait :property, :item do
      exec :create, args_pattern: %{payload: _}
    end

    trait :flagged, :item do
      exec :create, args_pattern: %{payload: %{flag: true}}
    end
  end

  test "a field another trait adds to a whole-map value is refused during search" do
    error =
      assert_raise SeedFactory.TraitResolutionError, fn ->
        init(%{}, RiderSchema) |> produce(item: [:flagged, property: %{years: 18}])
      end

    assert Exception.message(error) =~ "conflicts with"

    refute_received :rider_resolver_executed
  end
end
