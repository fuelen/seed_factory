defmodule SeedFactory.ExecutionTest do
  use ExUnit.Case, async: true

  alias SeedFactory.Execution

  describe "inspect" do
    test "with keyword args caller and no rebinding" do
      execution = %Execution{
        caller: {:produce, [{:user, []}, {:profile, [:active]}]},
        commands: [:create_org, :create_office, :create_user]
      }

      assert inspect(execution) ==
               "#execution[produce(user: [], profile: [:active]): create_user → create_office → create_org]"
    end

    test "with atom name caller" do
      execution = %Execution{
        caller: {:exec, :activate_user},
        commands: [:activate_user]
      }

      assert inspect(execution) ==
               "#execution[exec(activate_user): activate_user]"
    end

    test "with rebinding" do
      execution = %Execution{
        caller: {:produce, [{:user, []}]},
        commands: [:create_user],
        rebinding: %{user: :user2}
      }

      assert inspect(execution) ==
               "#execution[produce(user: []) as %{user: :user2}: create_user]"
    end
  end
end
