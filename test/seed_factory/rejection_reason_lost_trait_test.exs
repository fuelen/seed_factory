defmodule SeedFactory.RejectionReasonLostTraitTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # The :t decision lands on :make_e1, as :make_e2 dies on a parameter
    # check: its :blocked needs :active, a transition past the requested
    # :pending. A lost :t resolution leaves :make_e2 a candidate, so the :w
    # demand of :make_e1 reports its real reason, the parameter check;
    # :make_w2 collides with :make_e1 on :collide.
    command :make_blocked do
      resolve(fn _ -> {:ok, %{blocked: :pending_blocked}} end)

      produce :blocked
    end

    command :update_blocked do
      param :blocked, entity: :blocked

      resolve(fn _ -> {:ok, %{blocked: :active_blocked}} end)

      update :blocked
    end

    command :make_e1 do
      param :w, entity: :w

      resolve(fn _ -> {:ok, %{e: :e1, collide: :collide_e1}} end)

      produce :e
      produce :collide
    end

    command :make_e2 do
      param :blocked, entity: :blocked, with_traits: [:active]

      resolve(fn _ -> {:ok, %{e: :e2, w: :w2}} end)

      produce :e
      produce :w
    end

    command :make_w2 do
      resolve(fn _ -> {:ok, %{w: :w_alt, collide: :collide_w2}} end)

      produce :w
      produce :collide
    end

    trait :pending, :blocked do
      exec :make_blocked
    end

    trait :active, :blocked do
      from :pending
      exec :update_blocked
    end

    trait :t, :e do
      exec :make_e1
    end

    trait :t, :e do
      exec :make_e2
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a command that lost a trait resolution is reported for its own reasons", context do
    assert_raise SeedFactory.UnproducibleEntityError,
                 "cannot produce entity :w required by :make_e1: no candidate command fits the plan\n" <>
                   "- :make_e2 was rejected by a parameter check (TraitRestrictionConflictError)\n" <>
                   "- :make_w2 also produces :collide, already produced by :make_e1 in this plan",
                 fn ->
                   produce(context, [{:e, [:t]}, blocked: [:pending]])
                 end
  end
end
