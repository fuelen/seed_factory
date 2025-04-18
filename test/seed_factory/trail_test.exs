defmodule SeedFactory.TrailTest do
  use ExUnit.Case, async: true

  test "inspect" do
    trail =
      {:invite_user, [:pending], []}
      |> SeedFactory.Trail.new()
      |> SeedFactory.Trail.add_updated_by({:accept_invitation, [:active], [:pending]})
      |> SeedFactory.Trail.add_updated_by({:update_profile, [], []})
      |> SeedFactory.Trail.add_updated_by({:suspend_user, [:suspended], [:active]})

    assert inspect(trail) ==
             "#trail[invite_user: +[:pending] -> accept_invitation: +[:active] -[:pending] -> :update_profile -> suspend_user: +[:suspended] -[:active]]"
  end
end
