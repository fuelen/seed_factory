defmodule SeedFactory.RejectionReasonLostDeclarationTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :t is declared on :touch_e and :mark_e. The
    # request picks :touch_e, so :mark_e's declaration loses; :touch_e then
    # demands :t on its own :e param and has zero options. The report lists
    # every declaration, the lost one with the reason it is out of the running
    # (its command requires nothing that would form a cycle). The :mark_e route
    # dies too, as :cert's only producer re-produces :e.
    command :make_e do
      resolve(fn _ -> {:ok, %{e: :e1}} end)

      produce :e
    end

    command :touch_e do
      param :e, entity: :e, with_traits: [:t]

      resolve(fn _ -> {:ok, %{e: :e2}} end)

      update :e
    end

    command :mark_e do
      param :e, entity: :e
      param :cert, entity: :cert

      resolve(fn _ -> {:ok, %{e: :e3}} end)

      update :e
    end

    command :make_cert do
      resolve(fn _ -> {:ok, %{cert: :cert1, e: :e4}} end)

      produce :cert
      produce :e
    end

    trait :t, :e do
      exec :touch_e
    end

    trait :t, :e do
      exec :mark_e
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a lost declaration is reported as lost, not as a cycle", context do
    context = exec(context, :make_e)

    assert_raise SeedFactory.TraitResolutionError,
                 "cannot satisfy trait :t for entity :e (trait required by :touch_e command)\n" <>
                   "- candidate command :touch_e demands the trait it provides\n" <>
                   "- candidate command :mark_e lost the :t resolution to :touch_e in this plan",
                 fn ->
                   produce(context, e: [:t])
                 end
  end
end
