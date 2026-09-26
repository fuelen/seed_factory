defmodule SeedFactory.ParameterizedTraitContainerValueTest do
  use ExUnit.Case, async: true
  import SeedFactory

  defmodule Schema do
    use SeedFactory.Schema

    command :create_box do
      param :size do
        param :width, value: 10
        param :height, generate: fn -> 20 end

        param :depth do
          param :value, value: 1
          param :unit, value: :cm
        end
      end

      resolve(fn args ->
        send(self(), :box_created)
        {:ok, %{box: args.size}}
      end)

      produce :box
    end

    command :label_box do
      param :box,
        entity: :box,
        with_traits: [size: [width: 1, height: 2, depth: [value: 3, unit: :mm]]]

      resolve(fn args -> {:ok, %{label: args.box}} end)

      produce :label
    end

    command :ship_box do
      param :order do
        param :box, entity: :box, with_traits: [depth: [value: 3, unit: :mm]]
      end

      resolve(fn args -> {:ok, %{shipment: args.order.box}} end)

      produce :shipment
    end

    command :compare_boxes do
      param :left, entity: :box, with_traits: [depth: [value: 3, unit: :mm]]
      param :right, entity: :box, with_traits: [depth: %{value: 3, unit: :mm}]

      resolve(fn args -> {:ok, %{comparison: args.left == args.right}} end)
      produce :comparison
    end

    trait :size, :box do
      exec :create_box, args_pattern: %{size: _}
    end

    trait :depth, :box do
      exec :create_box, args_pattern: %{size: %{depth: _}}
    end
  end

  test "keyword values are tracked and matched in the shape the command receives" do
    ctx =
      produce(init(%{}, Schema), box: [size: [width: 1, height: 2, depth: [value: 3, unit: :mm]]])

    assert ctx.box == %{width: 1, height: 2, depth: %{value: 3, unit: :mm}}

    assert ctx.__seed_factory_meta__.current_traits.box == [
             depth: %{value: 3, unit: :mm},
             size: %{width: 1, height: 2, depth: %{value: 3, unit: :mm}}
           ]

    next = produce(ctx, box: [size: %{width: 1, height: 2, depth: %{value: 3, unit: :mm}}])
    assert hd(next.__seed_factory_meta__.execution_history).commands == []
  end

  test "with_traits keyword values are normalized when the schema compiles" do
    ctx = produce(init(%{}, Schema), :label)
    assert ctx.label == %{width: 1, height: 2, depth: %{value: 3, unit: :mm}}

    assert ctx.__seed_factory_meta__.current_traits.box == [
             depth: %{value: 3, unit: :mm},
             size: %{width: 1, height: 2, depth: %{value: 3, unit: :mm}}
           ]
  end

  test "exec and pre_exec read with_traits in the normalized shape" do
    ctx = exec(init(%{}, Schema), :label_box)
    assert ctx.label == %{width: 1, height: 2, depth: %{value: 3, unit: :mm}}

    ctx = pre_exec(init(%{}, Schema), :label_box)
    assert ctx.box == %{width: 1, height: 2, depth: %{value: 3, unit: :mm}}
    refute Map.has_key?(ctx, :label)
  end

  test "a value for a nested container is normalized, in with_traits of a nested entity param too" do
    ctx = produce(init(%{}, Schema), :shipment)
    assert ctx.shipment == %{width: 10, height: 20, depth: %{value: 3, unit: :mm}}
    assert {:depth, %{value: 3, unit: :mm}} in ctx.__seed_factory_meta__.current_traits.box
  end

  test "separate parameters can require the same value in keyword and map forms" do
    ctx = produce(init(%{}, Schema), :comparison)
    assert ctx.comparison
    assert {:depth, %{value: 3, unit: :mm}} in ctx.__seed_factory_meta__.current_traits.box
  end

  test "values that cannot match the command input are rejected before planning" do
    for {value, message} <- [
          {5, "expects a map or a keyword list for param :size, got: 5"},
          {nil, "expects a map or a keyword list for param :size, got: nil"},
          {[1, 2], "expects a map or a keyword list for param :size, got: [1, 2]"},
          {%URI{}, "expects a map or a keyword list for param :size, got: #{inspect(%URI{})}"},
          {[width: 1, height: 2, depth: 5],
           "expects a map or a keyword list at :depth of param :size, got: 5"},
          {%{width: 1, depth: %{value: 3, unit: :mm}},
           "needs every nested key of param :size, missing: :height"},
          {%{width: 1, height: 2, depth: %{value: 3}},
           "needs every nested key of param :size, missing: [:depth, :unit]"},
          {%{width: 1, height: 2, depth: %{value: 3, unit: :mm, scale: 2}, color: :red},
           "got keys that param :size does not define: :color, [:depth, :scale]"},
          {%{width: 1, depth: %{value: 3, unit: :mm}, color: :red},
           "needs every nested key of param :size, missing: :height; " <>
             "got keys that param :size does not define: :color"}
        ] do
      assert_raise ArgumentError, "trait :size of entity :box " <> message, fn ->
        produce(init(%{}, Schema), box: [size: value])
      end
    end

    refute_received :box_created
  end

  test "with_traits values that cannot match the command input fail the schema compilation" do
    for {label_params, message} <- [
          {quote(do: param(:box, entity: :box, with_traits: [size: 5])),
           "trait :size of entity :box expects a map or a keyword list for param :size, got: 5"},
          {quote do
             param :box, entity: :box, with_traits: [size: [width: 1]]
             param :other_box, entity: :box, with_traits: [size: %{width: 2}]
           end, "conflicting values for trait :size of entity :box: [%{width: 1}, %{width: 2}]"}
        ] do
      module = Module.concat(__MODULE__, "Invalid#{System.unique_integer([:positive])}")

      quoted =
        quote do
          defmodule unquote(module) do
            use SeedFactory.Schema

            command :create_box do
              param :size do
                param :width, value: 10
              end

              resolve(fn args -> {:ok, %{box: args.size}} end)
              produce :box
            end

            command :label_box do
              unquote(label_params)
              resolve(fn args -> {:ok, %{label: args.box}} end)
              produce :label
            end

            trait :size, :box do
              exec :create_box, args_pattern: %{size: _}
            end
          end
        end

      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        error =
          assert_raise Spark.Error.DslError, fn ->
            quoted |> Macro.to_string() |> Code.compile_string()
          end

        assert error.message == message
      end)
    end
  end
end
