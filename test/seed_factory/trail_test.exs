defmodule SeedFactory.TrailTest do
  use ExUnit.Case, async: true

  test "inspect" do
    trail =
      :invite_user
      |> SeedFactory.Trail.new()
      |> SeedFactory.Trail.add_updated_by(:accept_invitation)
      |> SeedFactory.Trail.add_updated_by(:update_profile)
      |> SeedFactory.Trail.add_updated_by(:suspend_user)

    assert inspect(trail) == "#trail[:invite_user -> :accept_invitation -> :update_profile -> :suspend_user]"
  end
end
