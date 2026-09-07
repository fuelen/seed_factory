defmodule SeedFactory.RequestedTraitRemovedTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Minimized from from_any stress seed 1, the last silent result in the
    # stress tier. :tag_e is the only exec of :t1 and also carries the
    # undeclared-in-the-request transition :t3, whose from list removes :t2 at
    # execution. A request for both :t1 and :t2 is therefore unsatisfiable:
    # every plan runs :tag_e after :t2 is applied and loses :t2. The plan is
    # refused loudly; the old core silently returned :e without :t2.
    command :create_e do
      resolve(fn _ -> {:ok, %{e: :e1}} end)

      produce :e
    end

    command :tag_e do
      param :e, entity: :e

      resolve(fn _ -> {:ok, %{e: :tagged_e}} end)

      update :e
    end

    trait :t2, :e do
      exec :create_e
    end

    trait :t1, :e do
      exec :tag_e
    end

    trait :t3, :e do
      from [:t1, :t2]
      exec :tag_e
    end

    # An independent cluster for the forced-order case: :prep_f removes :tf,
    # but :seal_f (the exec of :tf) requires :prep_f through :y, so the
    # removal is forced to run before the trait is applied and hits nothing.
    command :create_f do
      resolve(fn _ -> {:ok, %{f: :f1}} end)

      produce :f
    end

    command :prep_f do
      param :f, entity: :f

      resolve(fn _ -> {:ok, %{f: :prepped_f, y: :y1}} end)

      update :f
      produce :y
    end

    command :seal_f do
      param :f, entity: :f
      param :y, entity: :y

      resolve(fn _ -> {:ok, %{f: :sealed_f}} end)

      update :f
    end

    trait :tf, :f do
      exec :seal_f
    end

    trait :tx, :f do
      from :tf
      exec :prep_f
    end

    # An independent cluster for the re-adding case: :refresh_g transitions
    # from :tg but also declares :tg itself, so executing it never leaves the
    # entity without :tg - such a command is not a remover of :tg.
    command :make_g do
      resolve(fn _ -> {:ok, %{g: :g1}} end)

      produce :g
    end

    command :refresh_g do
      param :g, entity: :g

      resolve(fn _ -> {:ok, %{g: :refreshed_g, z: :z1}} end)

      update :g
      produce :z
    end

    trait :tg, :g do
      exec :make_g
    end

    trait :tg, :g do
      exec :refresh_g
    end

    trait :tg2, :g do
      from :tg
      exec :refresh_g
    end
  end

  use SeedFactory.Test, schema: Schema

  import TraitAssertions

  test "a chosen command removing a requested trait fails the plan loudly", context do
    assert_raise SeedFactory.TraitResolutionError,
                 "cannot satisfy trait :t2 for entity :e (requested trait)\n" <>
                   "- command :tag_e, chosen for the plan, applies :t3 and removes :t2",
                 fn ->
                   produce(context, e: [:t1, :t2])
                 end
  end

  test "a requested trait already sitting on the entity is protected too", context do
    context = exec(context, :create_e)

    assert_raise SeedFactory.TraitResolutionError,
                 "cannot satisfy trait :t2 for entity :e (requested trait)\n" <>
                   "- command :tag_e, chosen for the plan, applies :t3 and removes :t2",
                 fn ->
                   produce(context, e: [:t1, :t2])
                 end
  end

  test "the removal is fine while its victim is not requested", context do
    context = produce(context, e: [:t1])

    assert_trait(context, :e, [:t1, :t3])
  end

  test "a remover forced to run before the trait's command is legal", context do
    context = produce(context, f: [:tf])

    assert_trait(context, :f, [:tf, :tx])
  end

  test "a command re-adding the trait it transitions from is not a remover", context do
    context = produce(context, [:z, g: [:tg]])

    assert_trait(context, :g, [:tg, :tg2])
  end
end
