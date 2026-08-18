defmodule SeedFactory.DependencyWithTraitsTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :import_marketplace_order demands a :marketplace storefront through
    # with_traits while itself competing in the conflict groups that
    # [:shipped, :marketplace] builds, so the storefront producer is selected
    # under an unresolved requirement chain.
    command :create_region do
      resolve(fn _ ->
        {:ok, %{region: %{zone: :domestic}}}
      end)

      produce :region
    end

    command :create_overseas_region do
      resolve(fn _ ->
        {:ok, %{region: %{zone: :overseas}}}
      end)

      produce :region
    end

    command :create_storefront do
      resolve(fn _ ->
        {:ok, %{storefront: %{channel: nil, region: nil}}}
      end)

      produce :storefront
    end

    command :create_marketplace_storefront do
      param :region, entity: :region, with_traits: [:overseas]

      resolve(fn args ->
        {:ok, %{storefront: %{channel: :marketplace, region: args.region}}}
      end)

      produce :storefront
    end

    command :create_order do
      param :storefront, entity: :storefront

      resolve(fn args ->
        {:ok, %{order: %{channel: nil, status: :placed, storefront: args.storefront}}}
      end)

      produce :order
    end

    command :pack_order do
      param :order, entity: :order

      resolve(fn args ->
        {:ok, %{order: %{args.order | status: :packed}}}
      end)

      update :order
    end

    command :ship_order do
      param :order, entity: :order

      resolve(fn args ->
        {:ok, %{order: %{args.order | status: :shipped}}}
      end)

      update :order
    end

    command :import_marketplace_order do
      param :storefront, entity: :storefront, with_traits: [:marketplace]
      param :status, value: :packed

      resolve(fn args ->
        {:ok,
         %{order: %{channel: :marketplace, status: args.status, storefront: args.storefront}}}
      end)

      produce :order
    end

    trait :overseas, :region do
      exec :create_overseas_region
    end

    trait :marketplace, :storefront do
      exec :create_marketplace_storefront
    end

    trait :marketplace, :order do
      exec :import_marketplace_order
    end

    trait :packed, :order do
      exec :pack_order
    end

    trait :packed, :order do
      exec :import_marketplace_order, args_pattern: %{status: :packed}
    end

    trait :shipped, :order do
      from :packed
      exec :ship_order
    end

    trait :shipped, :order do
      exec :import_marketplace_order do
        args_match(fn args -> args.status == :shipped end)
        generate_args(fn -> %{status: :shipped} end)
      end
    end
  end

  use SeedFactory.Test, schema: Schema

  test "produce(order: [:shipped, :marketplace]) gives same result as produce(order: [:marketplace, :shipped])",
       context do
    context1 = produce(context, order: [:marketplace, :shipped])
    context2 = produce(context, order: [:shipped, :marketplace])

    assert context1.order == %{
             channel: :marketplace,
             status: :shipped,
             storefront: %{channel: :marketplace, region: %{zone: :overseas}}
           }

    assert context2.order == context1.order
  end

  test "produce([:storefront, :order]) ignores with_traits of the order producer that loses conflict resolution",
       context do
    context = produce(context, [:storefront, :order])

    assert context.storefront == %{channel: nil, region: nil}

    assert context.order == %{
             channel: nil,
             status: :placed,
             storefront: %{channel: nil, region: nil}
           }
  end
end
