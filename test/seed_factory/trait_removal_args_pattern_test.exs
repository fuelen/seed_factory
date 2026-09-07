defmodule SeedFactory.TraitRemovalArgsPatternTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :make_gadget declares the transition :t9 from :t1
    # under args_pattern %{special: true}, but the plan runs it with the
    # literal default false: the transition never fires and the command
    # removes nothing. :make_widget carries the mirror case, a pattern the
    # default satisfies, so its transition fires for sure.
    command :make_box do
      resolve(fn _ -> {:ok, %{box: :box1}} end)

      produce :box
    end

    command :make_gadget do
      param :box, entity: :box
      param :special, value: false

      resolve(fn _ -> {:ok, %{box: :box2, gadget: :gadget1}} end)

      update :box
      produce :gadget
    end

    command :make_widget do
      param :box, entity: :box
      param :mode, value: :on

      resolve(fn _ -> {:ok, %{box: :box3, widget: :widget1}} end)

      update :box
      produce :widget
    end

    trait :t1, :box do
      exec :make_box
    end

    trait :t9, :box do
      from :t1
      exec :make_gadget, args_pattern: %{special: true}
    end

    trait :t8, :box do
      from :t1
      exec :make_widget, args_pattern: %{mode: :on}
    end
  end

  use SeedFactory.Test, schema: Schema

  import TraitAssertions

  test "a transition whose pattern contradicts the literal args is not a remover", context do
    context = produce(context, [:gadget, box: [:t1]])

    assert context.gadget == :gadget1
    assert_trait(context, :box, [:t1])
  end

  test "a transition whose pattern the literal args satisfy removes for sure", context do
    assert_raise SeedFactory.TraitResolutionError,
                 "cannot satisfy trait :t1 for entity :box (requested trait)\n" <>
                   "- command :make_widget, chosen for the plan, applies :t8 and removes :t1",
                 fn ->
                   produce(context, [:widget, box: [:t1]])
                 end
  end
end
