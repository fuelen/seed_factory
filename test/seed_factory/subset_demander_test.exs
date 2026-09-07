defmodule SeedFactory.SubsetDemanderTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :assemble_beta produces the same entity as the producers of its own
    # dependency, so a demand for :beta grows the {:make_pair_one,
    # :make_pair_two} group to include it. The later demand for :material is a
    # subset of that group with :assemble_beta in the diff.
    command :make_pair_one do
      resolve(fn _ -> {:ok, %{alpha: :alpha_one, beta: :beta_one, material: :material_one}} end)

      produce :alpha
      produce :beta
      produce :material
    end

    command :make_pair_two do
      resolve(fn _ -> {:ok, %{alpha: :alpha_two, beta: :beta_two, material: :material_two}} end)

      produce :alpha
      produce :beta
      produce :material
    end

    command :assemble_beta do
      param :material, entity: :material

      resolve(fn args -> {:ok, %{beta: {:assembled, args.material}}} end)

      produce :beta
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a demand whose diff contains the demander keeps the demander alive", context do
    # The request order matters: :alpha builds the group before the :beta
    # demand grows it, only then :assemble_beta joins the group of the
    # producers of its own :material dependency.
    context = produce(context, [:alpha, :beta])

    assert %{alpha: _, beta: _} = context
  end

  test "the plan resolves regardless of the request order", context do
    context = produce(context, [:beta, :alpha])

    assert %{alpha: _, beta: _} = context
  end
end
