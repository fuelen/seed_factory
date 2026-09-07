defmodule SeedFactory.DoubleGrowTest do
  use ExUnit.Case, async: true

  # Producer sets: ent1 -> [a,b,c], ent2 -> [a,b,d], ent3 -> [a,b],
  # ent4 -> [a,b,c], ent5 -> [a,b,c,x].
  #
  # produce([:ent1, :ent2, :ent3, :ent4, :ent5]):
  #  - ent1 creates group [a,b,c], ent2 creates group [a,b,d]
  #  - ent3 ([a,b]) shrinks [a,b,d] to [a,b] (d removed)
  #  - ent4 ([a,b,c]) grows [a,b] to [a,b,c]: unresolved now holds two equal
  #    copies of [a,b,c] and each node holds two copies -> still consistent
  #  - ent5 ([a,b,c,x]) grows [a,b,c]: Enum.map grows BOTH unresolved copies,
  #    but Node.replace_conflict_group replaces only ONE copy per node ->
  #    unresolved and node conflict_groups diverge. The orphaned copy can
  #    never be resolved and resolve_conflicts loops forever.
  #
  # A plan of just :prod_a satisfies the request (it produces all five
  # entities). v0.8.2 resolves exactly that.
  defmodule Schema do
    use SeedFactory.Schema

    command :prod_a do
      resolve(fn _ ->
        {:ok, %{ent1: :e1_a, ent2: :e2_a, ent3: :e3_a, ent4: :e4_a, ent5: :e5_a}}
      end)

      produce :ent1
      produce :ent2
      produce :ent3
      produce :ent4
      produce :ent5
    end

    command :prod_b do
      resolve(fn _ ->
        {:ok, %{ent1: :e1_b, ent2: :e2_b, ent3: :e3_b, ent4: :e4_b, ent5: :e5_b}}
      end)

      produce :ent1
      produce :ent2
      produce :ent3
      produce :ent4
      produce :ent5
    end

    command :prod_c do
      resolve(fn _ -> {:ok, %{ent1: :e1_c, ent4: :e4_c, ent5: :e5_c}} end)

      produce :ent1
      produce :ent4
      produce :ent5
    end

    command :prod_d do
      resolve(fn _ -> {:ok, %{ent2: :e2_d}} end)

      produce :ent2
    end

    command :prod_x do
      resolve(fn _ -> {:ok, %{ent5: :e5_x}} end)

      produce :ent5
    end
  end

  use SeedFactory.Test, schema: Schema

  @tag timeout: 5_000
  test "two consecutive grows of the same group terminate", context do
    context = produce(context, [:ent1, :ent2, :ent3, :ent4, :ent5])

    assert context.ent1 == :e1_a
    assert context.ent5 == :e5_a
  end
end
