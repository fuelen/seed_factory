defmodule SeedFactory.TestTest do
  use ExUnit.Case, async: true
  use SeedFactory.Test, schema: SchemaExample

  describe "produce macro" do
    produce :org
    produce [:user, :project]

    test "check 1", context do
      for key <- [:org, :user, :project, :office] do
        assert Map.has_key?(context, key)
      end
    end

    produce org: :org1
    produce org: :org2

    test "check 2", context do
      assert Map.has_key?(context, :org1)
      assert Map.has_key?(context, :org2)
    end
  end
end
