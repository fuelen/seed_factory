defmodule SeedFactory.TelemetryTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    command :create_org do
      resolve(fn _ -> {:ok, %{org: %{id: 1}}} end)
      produce :org
    end

    command :create_user do
      param :org, entity: :org
      resolve(fn _ -> {:ok, %{user: %{id: 2}}} end)
      produce :user
    end

    command :reject_user do
      param :user, entity: :user
      resolve(fn _ -> {:error, :rejected} end)
      update :user
    end
  end

  use SeedFactory.Test, schema: Schema

  @events [
    [:seed_factory, :resolve, :start],
    [:seed_factory, :resolve, :stop],
    [:seed_factory, :resolve, :exception]
  ]

  setup do
    handler_id = {__MODULE__, make_ref()}
    :telemetry.attach_many(handler_id, @events, &__MODULE__.handle_event/4, self())
    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  def handle_event(event, measurements, metadata, test_pid) do
    if self() == test_pid do
      send(test_pid, {:telemetry, event, measurements, metadata})
    end
  end

  test "exec spans only the resolver and reports the exec call as caller for its dependencies",
       context do
    exec(context, :create_user)

    events =
      for _ <- 1..4 do
        receive do
          {:telemetry, [:seed_factory, :resolve, phase], _, %{command: command, caller: caller}} ->
            {command, phase, caller}
        after
          0 -> :missing
        end
      end

    assert events == [
             {:create_org, :start, {:exec, :create_user}},
             {:create_org, :stop, {:exec, :create_user}},
             {:create_user, :start, {:exec, :create_user}},
             {:create_user, :stop, {:exec, :create_user}}
           ]

    refute_received {:telemetry, _, _, _}
  end

  test "an error tuple from the resolver emits exception with ExecError", context do
    context = produce(context, :user)

    assert_raise SeedFactory.ExecError, fn -> exec(context, :reject_user) end

    assert_received {:telemetry, [:seed_factory, :resolve, :start], _, %{command: :reject_user}}

    assert_received {:telemetry, [:seed_factory, :resolve, :exception], %{duration: _},
                     %{
                       command: :reject_user,
                       caller: {:exec, :reject_user},
                       kind: :error,
                       reason: %SeedFactory.ExecError{command: :reject_user, error: :rejected},
                       stacktrace: _
                     }}

    refute_received {:telemetry, [:seed_factory, :resolve, :stop], _, %{command: :reject_user}}
  end
end
