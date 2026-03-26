defmodule SeedFactory.VerticalConflictTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    defp gen_id, do: :erlang.unique_integer([:positive])

    command :create_depot do
      resolve(fn _ -> {:ok, %{depot: %{id: gen_id(), type: :standard}}} end)
      produce :depot
    end

    command :create_priority_depot do
      resolve(fn _ -> {:ok, %{depot: %{id: gen_id(), type: :priority}}} end)
      produce :depot
    end

    command :create_rack do
      param :depot, entity: :depot
      resolve(fn args -> {:ok, %{rack: %{id: gen_id(), depot_id: args.depot.id}}} end)
      produce :rack
    end

    command :wrap_parcel do
      param :depot, entity: :depot
      param :rack, entity: :rack
      resolve(fn _ -> {:ok, %{parcel: %{id: gen_id(), source: :manual}}} end)
      produce :parcel
    end

    command :attach_tracking_label do
      param :parcel, entity: :parcel
      resolve(fn _ -> {:ok, %{tracking_label: %{id: gen_id(), source: :attached}}} end)
      produce :tracking_label
    end

    command :auto_wrap_parcel do
      param :rack, entity: :rack

      resolve(fn _ ->
        {:ok,
         %{
           parcel: %{id: gen_id(), source: :auto},
           tracking_label: %{id: gen_id(), source: :auto}
         }}
      end)

      produce :parcel
      produce :tracking_label
    end

    command :create_priority_shipment do
      param :depot, entity: :depot, with_traits: [:priority]
      param :parcel, entity: :parcel
      param :tracking_label, entity: :tracking_label
      resolve(fn args -> {:ok, %{shipment: %{id: gen_id(), depot_id: args.depot.id}}} end)
      produce :shipment
    end

    trait :priority, :depot do
      exec :create_priority_depot
    end

    trait :priority, :shipment do
      exec :create_priority_shipment
    end
  end

  use SeedFactory.Test, schema: Schema

  # Bug: when a trait resolves entity B to a specific command (create_priority_depot),
  # but another command in a conflict group (auto_wrap_parcel) depends on B through
  # an intermediary (rack → depot), the vertical conflict check prevents B's resolved
  # command from being recognized. A later no-trait request for B creates a new conflict
  # group where the wrong command (create_depot) wins.
  #
  # Dependency graph:
  #   create_priority_shipment
  #     ├── depot (with :priority trait) → create_priority_depot ✓
  #     ├── parcel (no traits) → conflict: [wrap_parcel, auto_wrap_parcel]
  #     └── tracking_label (no traits) → conflict: [attach_tracking_label, auto_wrap_parcel]
  #
  #   auto_wrap_parcel → rack → depot (no traits) ← vertical conflict chain
  #   wrap_parcel → depot (no traits), rack
  test "trait-resolved node is preserved despite vertical conflicts from other paths", context do
    context = produce(context, shipment: [:priority])

    assert context.depot.type == :priority
    assert context.shipment.depot_id == context.depot.id
  end
end
