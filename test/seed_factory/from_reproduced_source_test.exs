defmodule SeedFactory.FromReproducedSourceTest do
  use ExUnit.Case, async: true
  import SeedFactory
  import TraitAssertions

  for {suffix, source} <- [{"Single", :pending}, {"Alternatives", [:pending, :ready]}] do
    defmodule Module.concat(__MODULE__, suffix) do
      use SeedFactory.Schema

      command :create_item do
        param :value, value: 1
        resolve(fn args -> {:ok, %{item: %{value: args.value, pending: false}}} end)
        produce :item
      end

      command :delete_item do
        param :item, entity: :item
        resolve(fn _ -> {:ok, %{deleted: :deleted}} end)
        delete :item
        produce :deleted
      end

      command :recreate_item do
        param :deleted, entity: :deleted
        param :carry, value: false
        param :value, value: nil

        resolve(fn args ->
          {:ok, %{item: %{value: args.value, pending: false}, recreated: :recreated}}
        end)

        produce :item
        produce :recreated
      end

      command :prepare_item do
        param :item, entity: :item
        param :recreated, entity: :recreated

        resolve(fn args ->
          send(self(), :prepared)
          {:ok, %{item: %{args.item | pending: true}}}
        end)

        update :item
      end

      command :set_value do
        param :item, entity: :item
        param :recreated, entity: :recreated
        param :value

        resolve(fn args ->
          send(self(), {:transition_input, args.item})
          {:ok, %{item: %{args.item | value: args.value}}}
        end)

        update :item
      end

      command :create_report do
        param :item, entity: :item, with_traits: [value: 2]
        param :recreated, entity: :recreated, with_traits: [:plain]
        resolve(fn args -> {:ok, %{report: args.item}} end)
        produce :report
      end

      command :create_carried_report do
        param :item, entity: :item, with_traits: [value: 2]
        param :recreated, entity: :recreated, with_traits: [:carried_value]
        resolve(fn args -> {:ok, %{carried_report: args.item}} end)
        produce :carried_report
      end

      trait :plain, :recreated do
        exec :recreate_item, args_pattern: %{carry: false}
      end

      trait :carried_value, :recreated do
        exec :recreate_item, args_pattern: %{carry: true, value: 1}
      end

      trait :pending, :item do
        exec :prepare_item
      end

      trait :ready, :item do
        exec :prepare_item
      end

      trait :value, :item do
        exec :create_item, args_pattern: %{value: _}
      end

      trait :value, :item do
        exec :recreate_item, args_pattern: %{carry: true, value: _}
      end

      trait :value, :item do
        from source
        exec :set_value, args_pattern: %{value: _}
      end
    end
  end

  for schema <- [__MODULE__.Single, __MODULE__.Alternatives] do
    @schema schema

    test "a re-produced instance needs the transition source with #{inspect(schema)}" do
      context = %{} |> init(@schema) |> exec(:create_item) |> produce(:report)

      assert_receive :prepared
      assert_receive {:transition_input, %{value: nil, pending: true}}
      assert context.report == %{value: 2, pending: true}
      traits = if @schema == __MODULE__.Single, do: [:ready, {:value, 2}], else: [value: 2]
      assert_trait(context, :item, traits)
    end

    test "updating the same instance needs no source again with #{inspect(schema)}" do
      context =
        %{}
        |> init(@schema)
        |> exec(:create_item)
        |> exec(:delete_item)
        |> exec(:recreate_item)
        |> exec(:set_value, value: 1)

      assert_receive {:transition_input, %{value: nil, pending: false}}
      context = produce(context, item: [value: 2])

      refute_received :prepared
      assert_receive {:transition_input, %{value: 1, pending: false}}
      assert context.item.value == 2
      assert_trait(context, :item, value: 2)
    end

    test "a re-produced instance carrying the property needs no source with #{inspect(schema)}" do
      context = %{} |> init(@schema) |> exec(:create_item) |> produce(:carried_report)

      refute_received :prepared
      assert_receive {:transition_input, %{value: 1, pending: false}}
      assert context.carried_report == %{value: 2, pending: false}
      assert_trait(context, :item, value: 2)
    end
  end
end

defmodule SeedFactory.CarriedSourceCycleTest do
  use ExUnit.Case, async: true
  import SeedFactory

  defmodule Schema do
    use SeedFactory.Schema

    command :create_item do
      param :value, value: 1
      resolve(fn args -> {:ok, %{item: %{value: args.value}}} end)
      produce :item
    end

    command :delete_item do
      param :item, entity: :item

      resolve(fn _ ->
        send(self(), :deleted)
        {:ok, %{deleted: :deleted}}
      end)

      delete :item
      produce :deleted
    end

    command :recreate_item do
      param :deleted, entity: :deleted

      resolve(fn _ ->
        send(self(), :recreated)
        {:ok, %{item: %{value: nil}, recreated: :recreated}}
      end)

      produce :item
      produce :recreated
    end

    command :prepare_item do
      param :item, entity: :item
      param :report, entity: :report

      resolve(fn args ->
        send(self(), :prepared)
        {:ok, %{item: args.item}}
      end)

      update :item
    end

    command :set_value do
      param :item, entity: :item
      param :recreated, entity: :recreated
      param :value

      resolve(fn args ->
        send(self(), :transitioned)
        {:ok, %{item: %{args.item | value: args.value}}}
      end)

      update :item
    end

    command :create_report do
      param :item, entity: :item, with_traits: [value: 2]
      param :recreated, entity: :recreated
      resolve(fn args -> {:ok, %{report: args.item}} end)
      produce :report
    end

    trait :value, :item do
      from :pending
      exec :set_value, args_pattern: %{value: _}
    end

    trait :value, :item do
      exec :create_item, args_pattern: %{value: _}
    end

    trait :pending, :item do
      exec :prepare_item
    end
  end

  test "an unavailable source cannot be hidden by the carried-property route" do
    context = %{} |> init(Schema) |> exec(:create_item)

    error =
      assert_raise SeedFactory.TraitResolutionError, fn ->
        produce(context, :report)
      end

    assert error.message =~
             "command :recreate_item, chosen for the plan, re-produces :item without :value"

    refute_received :deleted
    refute_received :recreated
    refute_received :prepared
    refute_received :transitioned
  end
end
