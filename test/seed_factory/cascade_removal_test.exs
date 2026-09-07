defmodule SeedFactory.CascadeRemovalTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Producers: :e -> [cmd_k, cmd_m1], :f -> [cmd_k, cmd_m2], :g -> [cmd_m1, cmd_x]
    # produce([:g]) builds G0=[m1,x], then m1 demands :f -> G2=[k,m2],
    # then m2 demands :e -> G1=[k,m1]. Head-order resolves in favour of cmd_k
    # (head of G1). Removing m1 cascades into m2 and then into cmd_k itself.
    command :cmd_k do
      resolve(fn _ -> {:ok, %{e: :e_k, f: :f_k}} end)

      produce :e
      produce :f
    end

    command :cmd_m1 do
      param :f, entity: :f

      resolve(fn _ -> {:ok, %{e: :e_m1, g: :g_m1}} end)

      produce :e
      produce :g
    end

    command :cmd_x do
      resolve(fn _ -> {:ok, %{g: :g_x}} end)

      produce :g
    end

    command :cmd_m2 do
      param :e, entity: :e

      resolve(fn _ -> {:ok, %{f: :f_m2}} end)

      produce :f
    end
  end

  use SeedFactory.Test, schema: Schema

  test "conflict resolution survives a cascade that removes a later group member", context do
    context = produce(context, [:g])

    assert Map.has_key?(context, :g)
  end
end
