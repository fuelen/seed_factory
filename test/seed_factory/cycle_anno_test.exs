defmodule SeedFactory.CycleAnnoTest do
  use ExUnit.Case, async: true

  setup do
    debug_info? = Code.get_compiler_option(:debug_info)
    Code.put_compiler_option(:debug_info, true)
    on_exit(fn -> Code.put_compiler_option(:debug_info, debug_info?) end)
    :ok
  end

  # The guilty from edge sits on the second declaration of :b. The error must
  # point at its line, not at the innocent first declaration of the name.
  @schema """
  defmodule SeedFactory.CycleAnnoTest.Schema do
    use SeedFactory.Schema

    command :create_post do
      resolve(fn _ -> {:ok, %{post: :post}} end)
      produce :post
    end

    command :cmd_a do
      param :post, entity: :post
      resolve(fn _ -> {:ok, %{post: :post}} end)
      update :post
    end

    command :cmd_b1 do
      param :post, entity: :post
      resolve(fn _ -> {:ok, %{post: :post}} end)
      update :post
    end

    command :cmd_b2 do
      param :post, entity: :post
      resolve(fn _ -> {:ok, %{post: :post}} end)
      update :post
    end

    trait :a, :post do
      from :b
      exec :cmd_a
    end

    trait :b, :post do
      exec :cmd_b1
    end

    trait :b, :post do
      from :a
      exec :cmd_b2
    end
  end
  """

  test "the cycle error points at the declaration carrying the cycle edge" do
    guilty_line =
      @schema
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _n} -> String.contains?(line, "trait :b, :post") end)
      |> List.last()
      |> elem(1)

    error =
      try do
        ExUnit.CaptureIO.capture_io(:stderr, fn -> Code.compile_string(@schema) end)
        flunk("expected a DslError")
      rescue
        e in Spark.Error.DslError -> e
      end

    assert Exception.message(error) =~ "circular trait dependency detected: a -> b -> a"
    assert Exception.message(error) =~ "nofile:#{guilty_line}:"
  end
end
