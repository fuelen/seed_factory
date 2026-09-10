defmodule SeedFactory.RemoverBeforeApplierTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # :a_wipe, planned for w, strips :tagged, and :z_tag applies it; nothing
    # orders the two, so the plan orders :a_wipe first and the trait survives.
    # :use_e asks for the same through a parameter. In the :h cluster :strip,
    # planned for :use_ew, strips :t1 from e and :t3 from h: :use_eh needs
    # both traits, so :strip has to run after it, and :use_ew needs e with
    # :t1 after :strip, so :tag_e has to run after :strip too, but :use_eh
    # already needs :tag_e before :strip: no plan exists.
    command :create_e do
      resolve(fn _ ->
        send(self(), {:ran, :create_e})
        {:ok, %{e: :plain}}
      end)

      produce :e
    end

    command :a_wipe do
      param :e, entity: :e

      resolve(fn _ ->
        send(self(), {:ran, :a_wipe})
        {:ok, %{e: :wiped, w: :w1}}
      end)

      update :e
      produce :w
    end

    command :z_tag do
      param :e, entity: :e

      resolve(fn _ ->
        send(self(), {:ran, :z_tag})
        {:ok, %{e: :tagged}}
      end)

      update :e
    end

    command :use_e do
      param :e, entity: :e, with_traits: [:tagged]
      param :w, entity: :w

      resolve(fn args ->
        send(self(), {:ran, :use_e})
        {:ok, %{u: args.e}}
      end)

      produce :u
    end

    trait :tagged, :e do
      exec :z_tag
    end

    trait :wiped, :e do
      from :tagged
      exec :a_wipe
    end

    command :make_h do
      resolve(fn _ -> {:ok, %{h: :h1}} end)

      produce :h
    end

    command :tag_e do
      param :e, entity: :e

      resolve(fn _ -> {:ok, %{e: :e_t1}} end)

      update :e
    end

    command :tag_h do
      param :h, entity: :h

      resolve(fn _ -> {:ok, %{h: :h_t3}} end)

      update :h
    end

    command :strip do
      param :e, entity: :e
      param :h, entity: :h, with_traits: [:t3]

      resolve(fn _ -> {:ok, %{e: :e_stripped, h: :h_stripped, ws: :ws1}} end)

      update :e
      update :h
      produce :ws
    end

    command :use_eh do
      param :e, entity: :e, with_traits: [:t1]
      param :h, entity: :h, with_traits: [:t3]

      resolve(fn _ -> {:ok, %{c1: :c1}} end)

      produce :c1
    end

    command :use_ew do
      param :e, entity: :e, with_traits: [:t1]
      param :ws, entity: :ws

      resolve(fn _ -> {:ok, %{c2: :c2}} end)

      produce :c2
    end

    trait :t1, :e do
      exec :tag_e
    end

    trait :x1, :e do
      from :t1
      exec :strip
    end

    trait :t3, :h do
      exec :tag_h
    end

    trait :x3, :h do
      from :t3
      exec :strip
    end
  end

  use SeedFactory.Test, schema: Schema

  test "an independent remover runs before the requested trait is applied", context do
    context = context |> exec(:create_e) |> produce(e: [:tagged], w: [])

    assert :tagged in context.__seed_factory_meta__.current_traits.e
    assert context.w == :w1
    assert ran() == [:create_e, :a_wipe, :z_tag]
  end

  test "an independent remover runs before the trait a consumer asks for is applied",
       context do
    context = context |> exec(:create_e) |> produce(:u)

    assert context.u == :tagged
    assert ran() == [:create_e, :a_wipe, :z_tag, :use_e]
  end

  test "two consumers whose losses cannot both be sheltered fail the plan", context do
    assert_raise SeedFactory.TraitResolutionError,
                 "cannot satisfy trait :t1 for entity :e (trait required by :use_ew command)\n" <>
                   "- command :strip, chosen for the plan, applies :x1 and removes :t1",
                 fn -> produce(context, [:c1, :c2]) end
  end

  defp ran do
    receive do
      {:ran, name} -> [name | ran()]
    after
      0 -> []
    end
  end
end
