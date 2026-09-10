defmodule SeedFactory.CertainShelterPreferenceTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    command :make_e do
      resolve(fn _ -> {:ok, %{e: :ready}} end)
      produce :e
    end

    command :a_restore do
      param :e, entity: :e
      resolve(fn _ -> {:ok, %{e: :ready, z: :z}} end)
      update :e
      produce :z
    end

    command :wipe do
      param :e, entity: :e
      param :token, entity: :token
      resolve(fn _ -> {:ok, %{e: :wiped, w: :w}} end)
      update :e
      produce :w
    end

    command :prepare do
      resolve(fn _ -> {:ok, %{token: :token}} end)
      produce :token
    end

    command :b_restore do
      param :e, entity: :e
      param :w, entity: :w
      param :mode, generate: fn -> :partial end

      resolve(fn args ->
        e = if args.mode == :full, do: :ready, else: args.e
        {:ok, %{e: e, b: :b}}
      end)

      update :e
      produce :b
    end

    command :use_e do
      param :e, entity: :e, with_traits: [:ready]
      param :b, entity: :b
      resolve(fn args -> {:ok, %{result: args.e}} end)
      produce :result
    end

    trait :ready, :e do
      exec :make_e
    end

    trait :ready, :e do
      exec :a_restore
    end

    trait :wiped, :e do
      from :ready
      exec :wipe
    end

    trait :ready, :e do
      exec :b_restore, args_pattern: %{mode: :full}
    end
  end

  use SeedFactory.Test, schema: Schema

  for request <- [[:z, :result], [:result, :z]] do
    test "a possible restorer must not displace a certain one: #{inspect(request)}", context do
      initial = exec(context, :make_e)

      manual =
        initial
        |> exec(:prepare)
        |> exec(:wipe)
        |> exec(:b_restore)
        |> exec(:a_restore)
        |> exec(:use_e)

      assert %{z: :z, result: :ready} = manual
      assert %{z: :z, result: :ready} = produce(initial, unquote(request))
    end
  end
end
