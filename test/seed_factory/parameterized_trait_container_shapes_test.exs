defmodule SeedFactory.ParameterizedTraitContainerShapesTest do
  use ExUnit.Case, async: true
  import SeedFactory

  defmodule Schema do
    use SeedFactory.Schema

    command :create_box do
      param :size do
        param :width, value: 10
        param :height, value: 20
      end

      resolve(fn args -> {:ok, %{box: args.size}} end)

      produce :box
    end

    command :resize_width do
      param :box, entity: :box

      param :size do
        param :width, value: 1
      end

      resolve(fn args -> {:ok, %{box: %{args.box | width: args.size.width}}} end)

      update :box
    end

    trait :size, :box do
      exec :create_box, args_pattern: %{size: _}
    end

    trait :size, :box do
      exec :resize_width, args_pattern: %{size: _}
    end
  end

  defmodule PlainSchema do
    use SeedFactory.Schema

    command :create_box do
      param :size do
        param :width, value: 10
      end

      resolve(fn args -> {:ok, %{box: args.size}} end)

      produce :box
    end

    command :relabel do
      param :box, entity: :box
      param :size

      resolve(fn args -> {:ok, %{box: Map.put(args.box, :label, args.size)}} end)

      update :box
    end

    trait :size, :box do
      exec :relabel, args_pattern: %{size: _}
    end

    trait :size, :box do
      exec :create_box, args_pattern: %{size: _}
    end
  end

  defp commands(ctx) do
    ctx.__seed_factory_meta__.execution_history |> Enum.reverse() |> Enum.map(& &1.commands)
  end

  test "a value may fit any one of the container shapes of a trait" do
    ctx = produce(init(%{}, Schema), box: [size: %{width: 1, height: 2}])
    assert ctx.box == %{width: 1, height: 2}
    assert ctx.__seed_factory_meta__.current_traits.box == [size: %{width: 1, height: 2}]
    assert commands(ctx) == [[:create_box]]

    ctx = produce(init(%{}, Schema), box: [size: [width: 5]])
    assert ctx.box == %{width: 5, height: 20}
    assert ctx.__seed_factory_meta__.current_traits.box == [size: %{width: 5}]
    assert commands(ctx) == [[:resize_width, :create_box]]

    ctx = produce(ctx, box: [size: %{width: 5}])
    assert commands(ctx) == [[:resize_width, :create_box], []]
  end

  test "a value fitting no shape names what each declaration misses" do
    assert_raise ArgumentError,
                 """
                 trait :size of entity :box fits no declaration:
                   * :create_box needs every nested key of param :size, missing: :width
                   * :resize_width needs every nested key of param :size, missing: :width; \
                 got keys that param :size does not define: :height\
                 """,
                 fn -> produce(init(%{}, Schema), box: [size: %{height: 2}]) end

    assert_raise ArgumentError,
                 "trait :size of entity :box expects a map or a keyword list for param :size, got: 5",
                 fn -> produce(init(%{}, Schema), box: [size: 5]) end
  end

  test "a container shape normalizes a value a plain declaration also takes" do
    ctx = produce(init(%{}, PlainSchema), box: [size: [width: 3]])
    assert ctx.box == %{width: 3}
    assert ctx.__seed_factory_meta__.current_traits.box == [size: %{width: 3}]
    assert commands(ctx) == [[:create_box]]
  end

  test "a plain declaration takes a value no container shape fits" do
    for value <- [5, %{height: 3}, [height: 3], [1, 2], [], %URI{}] do
      ctx = produce(init(%{}, PlainSchema), box: [size: value])
      assert ctx.box == %{width: 10, label: value}
      assert ctx.__seed_factory_meta__.current_traits.box == [size: value]
      assert commands(ctx) == [[:relabel, :create_box]]
    end
  end
end
