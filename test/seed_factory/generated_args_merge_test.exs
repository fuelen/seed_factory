defmodule SeedFactory.GeneratedArgsMergeTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # The generated args of :tagged overlap the pattern of :leveled inside a
    # nested map, with the same value for :level: no conflict, both apply.
    command :create_doc do
      param :opts do
        param :level, value: 0
        param :tag, value: nil
      end

      resolve(fn args -> {:ok, %{doc: args.opts}} end)

      produce :doc
    end

    trait :leveled, :doc do
      exec :create_doc, args_pattern: %{opts: %{level: 2}}
    end

    trait :tagged, :doc do
      exec :create_doc,
        args_match: fn args -> args.opts.tag == :t end,
        generate_args: fn -> %{opts: %{tag: :t, level: 2}} end
    end
  end

  use SeedFactory.Test, schema: Schema

  import TraitAssertions

  test "generated args agreeing with a pattern inside a nested map merge with it", context do
    context = produce(context, doc: [:leveled, :tagged])

    assert_trait(context, :doc, [:leveled, :tagged])
    assert context.doc == %{level: 2, tag: :t}
  end
end
