defmodule SeedFactory.PartialResolutionTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    defp gen_id, do: :erlang.unique_integer([:positive])

    command :create_thing do
      resolve(fn _ -> {:ok, %{thing: %{id: gen_id(), stage: :initial}}} end)
      produce :thing
    end

    command :upgrade_via_path_a do
      param :thing, entity: :thing
      param :mode, value: :standard

      resolve(fn args -> {:ok, %{thing: %{args.thing | stage: {:path_a, args.mode}}}} end)
      update :thing
    end

    command :upgrade_via_path_b do
      param :thing, entity: :thing
      resolve(fn args -> {:ok, %{thing: %{args.thing | stage: :path_b}}} end)
      update :thing
    end

    command :finalize_from_a do
      param :thing, entity: :thing
      resolve(fn args -> {:ok, %{thing: %{args.thing | stage: :final_a}}} end)
      update :thing
    end

    command :finalize_from_b do
      param :thing, entity: :thing
      resolve(fn args -> {:ok, %{thing: %{args.thing | stage: :final_b}}} end)
      update :thing
    end

    trait :basic, :thing do
      exec :create_thing
    end

    # Two traits share the same command but are distinguished by args_pattern.
    # Only one matches at execution time, so the trail records only that trait.
    trait :upgraded_a, :thing do
      from :basic
      exec :upgrade_via_path_a, args_pattern: %{mode: :standard}
    end

    trait :upgraded_a_alt, :thing do
      from :basic

      exec :upgrade_via_path_a do
        args_match(fn args -> args.mode == :alt end)
        generate_args(fn -> %{mode: :alt} end)
      end
    end

    trait :upgraded_b, :thing do
      from :basic
      exec :upgrade_via_path_b
    end

    # :final conflict group: two entries with different from prerequisites.
    # When upgrade_via_path_a was executed with :upgraded_a_alt (mode: :alt),
    # resolving the :upgraded_a prerequisite hits trait_mismatch,
    # while :upgraded_b resolves normally → partial resolution in resolve_trait_dependencies.
    trait :final, :thing do
      from :upgraded_a
      exec :finalize_from_a
    end

    trait :final, :thing do
      from :upgraded_b
      exec :finalize_from_b
    end
  end

  use SeedFactory.Test, schema: Schema

  test "partial trait resolution: one from-path fails, the other succeeds", context do
    # Step 1: produce thing with :upgraded_a_alt trait.
    # upgrade_via_path_a executes with mode: :alt, so only :upgraded_a_alt is recorded.
    context = produce(context, thing: [:upgraded_a_alt])
    assert context.thing.stage == {:path_a, :alt}

    # Step 2: request :final trait.
    # - from :upgraded_a → trait_mismatch (upgrade_via_path_a ran with :upgraded_a_alt, not :upgraded_a)
    # - from :upgraded_b → resolves normally
    # This exercises the {:partial, ...} branch in resolve_trait_dependencies.
    context = produce(context, thing: [:final])
    assert context.thing.stage in [:final_a, :final_b]
  end
end
