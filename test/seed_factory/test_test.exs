defmodule SeedFactory.TestTest do
  use ExUnit.Case, async: true
  use SeedFactory.Test, schema: SchemaExample

  describe "produce macro check 1" do
    produce :org
    produce [:user, :project]

    test "check", context do
      for key <- [:org, :user, :project, :office] do
        assert Map.has_key?(context, key)
      end
    end
  end

  describe "produce macro check 2" do
    produce org: :org1
    produce org: :org2

    test "check", context do
      assert Map.has_key?(context, :org1)
      assert Map.has_key?(context, :org2)
    end
  end

  describe "produce macro check 3" do
    produce project: [:with_virtual_file]

    test "check", context do
      assert Map.has_key?(context, :project)
      assert Map.has_key?(context, :virtual_file)
    end
  end

  test "call produce/1 in runtime" do
    assert_raise(
      ArgumentError,
      "produce/1 cannot be called in runtime, probably you forgot to pass context as an argument",
      fn ->
        defmodule MyTest do
          use ExUnit.Case, async: true
          use SeedFactory.Test, schema: SchemaExample

          test "test" do
            produce :org
          end
        end
      end
    )
  end
end
