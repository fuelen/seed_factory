defmodule SeedFactory.PreProducePhantomDeleterTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # A phantom never executes, so its delete cannot legalize a second real
    # producer of an entity. Here the dependencies of the request genuinely
    # need two :gadget producers (:make_socket collaterally, :make_special_gadget
    # for the :special trait) and the only deleter of :gadget is the requested
    # :make_wiper, which pre_produce prunes. Accepting that plan would raise
    # EntityAlreadyExistsError halfway through the execution; refusing at
    # planning is the honest answer.
    command :make_wiper do
      resolve(fn _ -> {:ok, %{wiper: :wiper}} end)

      produce :wiper
      delete :gadget
    end

    command :make_socket do
      resolve(fn _ -> {:ok, %{socket: :socket, gadget: :plain_gadget}} end)

      produce :socket
      produce :gadget
    end

    command :make_carrier do
      param :socket, entity: :socket

      resolve(fn _ -> {:ok, %{carrier: :carrier}} end)

      produce :carrier
    end

    command :make_special_gadget do
      resolve(fn _ -> {:ok, %{gadget: :special_gadget}} end)

      produce :gadget
    end

    command :make_holder do
      param :gadget, entity: :gadget, with_traits: [:special]

      resolve(fn _ -> {:ok, %{holder: :holder}} end)

      produce :holder
    end

    trait :special, :gadget do
      exec :make_special_gadget
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a phantom deleter does not legalize two real producers", context do
    assert_raise SeedFactory.UnproducibleEntityError, fn ->
      pre_produce(context, [:wiper, :carrier, :holder])
    end
  end
end
