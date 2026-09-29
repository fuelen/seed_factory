defmodule SeedFactory.FromAlternativeDeliveryTest do
  use ExUnit.Case, async: true

  for {suffix, sources, source} <- [
        {"Forward", [:pending, :ready], :generated},
        {"Reverse", [:ready, :pending], :generated},
        {"EntityForward", [:pending, :ready], :entity},
        {"EntityReverse", [:ready, :pending], :entity}
      ] do
    name = Module.concat(__MODULE__, suffix)

    defmodule name do
      use SeedFactory.Schema

      command :create_user do
        resolve(fn _ ->
          send(self(), :created)
          {:ok, %{user: %{mode: Process.get(:from_mode)}}}
        end)

        produce :user
      end

      command :audit do
        param :user, entity: :user
        param :mode, generate: fn -> Process.get(:from_mode) end

        resolve(fn args ->
          send(self(), :audited)
          {:ok, %{user: args.user, audit: :audit}}
        end)

        update :user
        produce :audit
      end

      command :close do
        param :user, entity: :user
        param :audit, entity: :audit

        resolve(fn args ->
          send(self(), :closed)
          {:ok, %{user: args.user}}
        end)

        update :user
      end

      trait :pending, :user do
        exec :create_user
      end

      trait :ready, :user do
        exec :create_user
      end

      trait :pending_removed, :user do
        from :pending

        exec :audit,
          args_pattern:
            if(source == :generated, do: %{mode: :pending}, else: %{user: %{mode: :pending}})
      end

      trait :ready_removed, :user do
        from :ready

        exec :audit,
          args_pattern:
            if(source == :generated, do: %{mode: :ready}, else: %{user: %{mode: :ready}})
      end

      trait :both_removed, :user do
        from [:pending, :ready]

        exec :audit,
          args_pattern:
            if(source == :generated, do: %{mode: :both}, else: %{user: %{mode: :both}})
      end

      trait :closed, :user do
        from sources
        exec :close
      end
    end
  end

  import SeedFactory
  alias __MODULE__.{Forward, Reverse, EntityForward, EntityReverse}

  for {schema, first_source} <- [
        {Forward, :pending},
        {Reverse, :ready},
        {EntityForward, :pending},
        {EntityReverse, :ready}
      ],
      existing? <- [false, true] do
    @schema schema
    @first_source first_source
    @existing existing?
    @deferred not existing? and schema in [EntityForward, EntityReverse]

    test "a surviving source suffices with #{inspect(schema)}, existing: #{existing?}" do
      for mode <- [:pending, :ready, :neither] do
        Process.put(:from_mode, mode)
        ctx = SeedFactory.Context.init(%{}, @schema)
        ctx = if @existing, do: produce(ctx, :user), else: ctx
        ctx = produce(ctx, user: [:closed])

        assert :closed in ctx.__seed_factory_meta__.current_traits.user
        refute :pending in ctx.__seed_factory_meta__.current_traits.user
        refute :ready in ctx.__seed_factory_meta__.current_traits.user
        assert_receive :closed
      end
    end

    test "losing every source fails before the transition with #{inspect(schema)}, existing: #{existing?}" do
      Process.put(:from_mode, :both)
      ctx = SeedFactory.Context.init(%{}, @schema)
      ctx = if @existing, do: produce(ctx, :user), else: ctx
      if @existing, do: assert_receive(:created)

      error =
        assert_raise SeedFactory.MissingRequestedTraitError, fn ->
          produce(ctx, user: [:closed])
        end

      assert Enum.sort(error.trait) == [:pending, :ready]
      assert error.required_by == :close
      assert error.removed_by == :audit
      assert error.removed_when == :planned
      assert error.removed_trait == @first_source
      assert error.message =~ "none of the source traits"
      assert error.message =~ "command :audit removes #{inspect(@first_source)}"

      if @deferred do
        assert_receive :created
      else
        refute_received :created
      end

      refute_received :audited
      refute_received :closed
    end
  end
end
