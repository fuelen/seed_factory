defmodule SeedFactory.ExistingInstanceCandidateChoiceTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Minimized from container stress seed 110. Both
    # candidates for :t collaterally re-produce an entity that already sits in
    # the context, so the duplicate filter keeps them all. Only :t_via_b has a
    # valid route: its :n dependency pulls in :del_b, whose delete of :b
    # legalizes the re-produce (del_b -> t_via_b). The context instance counts
    # as produced before the plan starts, so :t_via_a (re-producing :a with no
    # deleter of :a anywhere) is rejected and backtracking lands on :t_via_b;
    # accepting :t_via_a means EntityAlreadyExistsError at execution.
    command :make_ab do
      resolve(fn _ -> {:ok, %{a: :a1, b: :b1}} end)

      produce :a
      produce :b
    end

    command :t_via_a do
      resolve(fn _ -> {:ok, %{t: :t_from_a, a: :a2}} end)

      produce :t
      produce :a
    end

    command :t_via_b do
      param :n, entity: :n

      resolve(fn _ -> {:ok, %{t: :t_from_b, b: :b2}} end)

      produce :t
      produce :b
    end

    command :del_b do
      param :b, entity: :b

      resolve(fn _ -> {:ok, %{n: :n1}} end)

      produce :n
      delete :b
    end
  end

  use SeedFactory.Test, schema: Schema

  test "the candidate with a deleter route wins over the EAE-doomed one", context do
    context = context |> exec(:make_ab) |> produce(:t)

    assert context.t == :t_from_b
    assert context.b == :b2
    assert context.a == :a1
  end
end
