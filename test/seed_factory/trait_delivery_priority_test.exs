defmodule SeedFactory.TraitDeliveryPriorityTest do
  use ExUnit.Case, async: false

  test "a certain addition wins over an uncertain removal in either declaration order" do
    addition =
      quote do
        trait :ready, :user do
          exec :mark_user, args_pattern: %{keep: true}
        end
      end

    removal =
      quote do
        trait :changed, :user do
          from :ready

          exec :mark_user,
            args_match: fn args -> args.user.active end,
            generate_args: fn -> %{} end
        end
      end

    for declarations <- [[addition, removal], [removal, addition]], active <- [false, true] do
      module = Module.concat(__MODULE__, "Schema#{System.unique_integer([:positive])}")

      Module.create(
        module,
        quote do
          use SeedFactory.Schema

          command :create_user do
            resolve(fn _ -> {:ok, %{user: %{active: unquote(active)}}} end)
            produce :user
          end

          command :mark_user do
            param :user, entity: :user
            param :keep, value: true
            resolve(fn args -> {:ok, %{user: args.user, receipt: :marked}} end)
            update :user
            produce :receipt
          end

          trait :ready, :user do
            exec :create_user
          end

          unquote_splicing(declarations)
        end,
        Macro.Env.location(__ENV__)
      )

      ctx = SeedFactory.init(%{}, module) |> SeedFactory.produce([:receipt, user: [:ready]])
      assert ctx.receipt == :marked
      assert :ready in ctx.__seed_factory_meta__.current_traits.user
      assert :changed in ctx.__seed_factory_meta__.current_traits.user == active
    end
  end
end
