defmodule SeedFactory.ConsumerEntityDeletedTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :use_both needs e, f and k; the only f comes from :drop_e, which deletes
    # the only e, and :remake_e, the only source of k, re-produces e after the
    # deletion. The :g cluster has no such command, so no plan exists there.
    command :make_e do
      resolve(fn _ -> {:ok, %{e: :e1}} end)

      produce :e
    end

    command :drop_e do
      param :e, entity: :e

      resolve(fn _ -> {:ok, %{f: :f1}} end)

      delete :e
      produce :f
    end

    command :remake_e do
      param :f, entity: :f

      resolve(fn _ -> {:ok, %{e: :e2, k: :k1}} end)

      produce :e
      produce :k
    end

    command :use_both do
      param :e, entity: :e
      param :f, entity: :f
      param :k, entity: :k

      resolve(fn args -> {:ok, %{u: args.e}} end)

      produce :u
    end

    command :make_g do
      resolve(fn _ -> {:ok, %{g: :g1}} end)

      produce :g
    end

    command :drop_g do
      param :g, entity: :g

      resolve(fn _ -> {:ok, %{h: :h1}} end)

      delete :g
      produce :h
    end

    command :use_both_g do
      param :g, entity: :g
      param :h, entity: :h

      resolve(fn args ->
        send(self(), {:used, args.g})
        {:ok, %{v: :v1}}
      end)

      produce :v
    end
  end

  use SeedFactory.Test, schema: Schema

  @message "cannot produce entity :g required by :use_both_g: " <>
             "command :drop_g, chosen for the plan, deletes it before :use_both_g runs"

  test "a consumer depending on the deleter of its required entity fails the plan loudly",
       context do
    assert_raise SeedFactory.UnproducibleEntityError, @message, fn -> produce(context, :v) end

    refute_received {:used, _}
  end

  test "an entity already in the context is protected the same way", context do
    context = exec(context, :make_g)

    assert_raise SeedFactory.UnproducibleEntityError, @message, fn -> produce(context, :v) end

    refute_received {:used, _}
  end

  test "the consumer reads the instance re-produced after the deleter", context do
    context = produce(context, :u)

    assert context.u == :e2
    assert context.e == :e2
  end
end
