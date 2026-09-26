defmodule SeedFactory.ParameterizedTraitsSchemaTest do
  use ExUnit.Case, async: false

  defmodule PatternExpression do
    defmacro constant(_syntax), do: 42
  end

  defp compile_schema(traits) do
    module = Module.concat(__MODULE__, "Schema#{System.unique_integer([:positive])}")

    quoted =
      quote do
        defmodule unquote(module) do
          use SeedFactory.Schema

          command :create do
            param :value
            param :other
            resolve(fn args -> {:ok, %{item: args}} end)
            produce :item
          end

          command :change do
            param :item, entity: :item
            param :value
            resolve(fn args -> {:ok, %{item: args.value}} end)
            update :item
          end

          unquote(traits)
        end
      end

    quoted |> Macro.to_string() |> Code.compile_string()

    module
  end

  defp assert_invalid(pattern, traits) do
    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      assert_raise Spark.Error.DslError, pattern, fn -> compile_schema(traits) end
    end)
  end

  defp assert_invalid_elixir(traits) do
    output =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert_raise CompileError, fn -> compile_schema(traits) end
      end)

    assert output =~ "invalid use of _"
  end

  test "multiple placeholders are rejected at schema compilation" do
    assert_invalid(
      ~r/exactly one _/,
      quote do
        trait :property, :item do
          exec :create, args_pattern: %{value: _, other: _}
        end
      end
    )
  end

  test "as is reserved for rebinding, not a parameterized trait name" do
    assert_invalid(
      ~r/:as is reserved/,
      quote do
        trait :as, :item do
          exec :create, args_pattern: %{value: _}
        end
      end
    )
  end

  test "map update expressions retain their ordinary meaning in patterns" do
    schema =
      compile_schema(
        quote do
          @base %{value: 1, other: 2}
          trait :fixed, :item do
            exec :create, args_pattern: %{@base | value: 42}
          end
        end
      )

    ctx = %{} |> SeedFactory.init(schema) |> SeedFactory.produce(item: [:fixed])
    assert ctx.item == %{value: 42, other: 2}
  end

  test "placeholders outside a literal map value are rejected" do
    for pattern <- [
          quote(do: %{_ => 1}),
          quote(do: %{value: [_]}),
          quote(do: %{value: {:tag, _}}),
          quote(do: %{value: %URI{host: _}}),
          quote(do: %{%{value: 1, other: 2} | value: _}),
          quote(do: Map.put(%{}, :value, _))
        ] do
      assert_invalid_elixir(
        quote do
          trait :property, :item do
            exec :create, args_pattern: unquote(pattern)
          end
        end
      )
    end
  end

  test "patterns must still evaluate to maps" do
    assert_invalid(
      ~r/expected map/,
      quote do
        trait :property, :item do
          exec :create, args_pattern: [value: 1]
        end
      end
    )
  end

  test "declarations of one name cannot mix parameterized and ordinary traits" do
    assert_invalid(
      ~r/must agree/,
      quote do
        trait :property, :item do
          exec :create, args_pattern: %{value: _}
        end

        trait :property, :item do
          exec :change, args_pattern: %{value: 1}
        end
      end
    )
  end

  test "from cannot implicitly choose a parameterized prerequisite's value" do
    assert_invalid(
      ~r/parameterized traits cannot be used in from/,
      quote do
        trait :property, :item do
          exec :create, args_pattern: %{value: _}
        end

        trait :changed, :item do
          from :property
          exec :change
        end
      end
    )
  end

  test "ordinary expressions, aliases and module attributes in patterns still work" do
    schema =
      compile_schema(
        quote do
          alias Map, as: PatternMap
          @fixed %{value: 42}
          trait :fixed, :item do
            exec :create, args_pattern: PatternMap.merge(@fixed, %{other: 1 + 2})
          end
        end
      )

    ctx = %{} |> SeedFactory.init(schema) |> SeedFactory.produce(item: [:fixed])
    assert ctx.item == %{value: 42, other: 3}
  end

  test "included schemas preserve compiled parameterized patterns" do
    fragment =
      compile_schema(
        quote do
          trait :property, :item do
            exec :create, args_pattern: %{value: _}
          end
        end
      )

    module = Module.concat(__MODULE__, "Included#{System.unique_integer([:positive])}")

    Code.compile_quoted(
      quote do
        defmodule unquote(module) do
          use SeedFactory.Schema
          include_schema unquote(fragment)
        end
      end
    )

    ctx = %{} |> SeedFactory.init(module) |> SeedFactory.produce(item: [property: 42])
    assert ctx.item.value == 42
    assert ctx.__seed_factory_meta__.current_traits.item == [property: 42]
  end

  test "quoted underscores and DSL-looking calls are argument data" do
    expressions = [
      "quote(do: _)",
      "quote(do: args_pattern(%{value: _}))",
      "quote(do: quote(do: _))",
      "quote(unquote: false, do: unquote(_))",
      "quote(bind_quoted: [x: match?({:ok, _}, {:ok, 1})], do: x)",
      "quote(do: unquote(match?({:ok, _}, {:ok, 1})))",
      "quote(do: quote(do: unquote(unquote(match?({:ok, _}, {:ok, 1})))))"
    ]

    for source <- expressions do
      expression = Code.string_to_quoted!(source)
      {expected, _} = Code.eval_string(source)

      schema =
        compile_schema(
          quote do
            trait :property, :item do
              exec :create, args_pattern: %{value: unquote(expression), other: _}
            end
          end
        )

      ctx = SeedFactory.init(%{}, schema) |> SeedFactory.produce(item: [property: 42])
      assert Macro.to_string(ctx.item.value) == Macro.to_string(expected)
      assert ctx.item.other == 42
    end
  end

  test "nested quotes keep their unquotes as data" do
    for options <- ["", "unquote: false, ", "bind_quoted: [x: 1], ", "unquote: true, "] do
      source = "quote(do: quote(#{options}do: unquote(unquote(_))))"
      expression = Code.string_to_quoted!(source)
      {expected, _} = Code.eval_string(source)

      schema =
        compile_schema(
          quote do
            trait :quoted, :item do
              exec :create, args_pattern: %{value: unquote(expression)}
            end

            trait :property, :item do
              exec :create, args_pattern: %{value: unquote(expression), other: _}
            end
          end
        )

      for request <- [[:quoted], [property: 42]] do
        ctx = SeedFactory.init(%{}, schema) |> SeedFactory.produce(item: request)
        assert Macro.to_string(ctx.item.value) == Macro.to_string(expected)
        if request == [property: 42], do: assert(ctx.item.other == 42)
      end
    end
  end

  test "custom macros retain control of their underscore arguments" do
    for expression <- [quote(do: constant(_)), quote(do: CustomPattern.constant(_))] do
      schema =
        compile_schema(
          quote do
            alias SeedFactory.ParameterizedTraitsSchemaTest.PatternExpression, as: CustomPattern
            require CustomPattern
            import CustomPattern, warn: false

            trait :property, :item do
              exec :create, args_pattern: %{value: unquote(expression), other: _}
            end
          end
        )

      ctx = SeedFactory.init(%{}, schema) |> SeedFactory.produce(item: [property: 7])
      assert ctx.item == %{value: 42, other: 7}
      assert {:property, 7} in ctx.__seed_factory_meta__.current_traits.item
    end
  end

  test "active unquotes cannot hide an invalid placeholder" do
    for source <- [
          "quote(do: unquote(_))",
          "quote(do: unquote_splicing(_))",
          "quote(bind_quoted: [x: _], do: x)"
        ] do
      expression = Code.string_to_quoted!(source)

      assert_invalid_elixir(
        quote do
          trait :invalid, :item do
            exec :create, args_pattern: %{value: unquote(expression)}
          end
        end
      )
    end
  end

  test "match? wildcards remain ordinary patterns alongside a trait parameter" do
    expressions = [
      quote(do: match?({:ok, _}, {:ok, 1})),
      quote(do: Kernel.match?({:ok, _}, {:ok, 1})),
      quote(do: PatternKernel.match?({:ok, _}, {:ok, 1})),
      quote(do: Enum.any?([{:ok, 1}], &match?({:ok, _}, &1))),
      quote(do: Enum.any?([{:ok, 1}], &Kernel.match?({:ok, _}, &1)))
    ]

    for expression <- expressions do
      schema =
        compile_schema(
          quote do
            alias Kernel, as: PatternKernel, warn: false

            trait :fixed, :item do
              exec :create, args_pattern: %{value: unquote(expression)}
            end

            trait :property, :item do
              exec :create do
                args_pattern(%{value: unquote(expression), other: _})
              end
            end
          end
        )

      ctx = SeedFactory.init(%{}, schema)
      assert SeedFactory.produce(ctx, item: [:fixed]).item.value == true
      produced = SeedFactory.produce(ctx, item: [property: 42])
      assert produced.item == %{value: true, other: 42}
      assert {:property, 42} in produced.__seed_factory_meta__.current_traits.item
    end
  end

  test "destructure wildcards remain ordinary patterns alongside a trait parameter" do
    for call <- ["destructure", "Kernel.destructure", "PatternKernel.destructure"] do
      expression = Code.string_to_quoted!("(#{call}([_, x], [1, 2]); x)")

      schema =
        compile_schema(
          quote do
            alias Kernel, as: PatternKernel, warn: false

            trait :fixed, :item do
              exec :create, args_pattern: %{value: unquote(expression)}
            end

            trait :property, :item do
              exec :create do
                args_pattern(%{value: unquote(expression), other: _})
              end
            end
          end
        )

      ctx = SeedFactory.init(%{}, schema)
      assert SeedFactory.produce(ctx, item: [:fixed]).item.value == 2
      produced = SeedFactory.produce(ctx, item: [property: 42])
      assert produced.item == %{value: 2, other: 42}
      assert {:property, 42} in produced.__seed_factory_meta__.current_traits.item
    end
  end

  test "destructure does not hide a placeholder in its value expression" do
    for call <- ["destructure", "Kernel.destructure", "PatternKernel.destructure"] do
      expression = Code.string_to_quoted!("#{call}([_, x], _)")

      assert_invalid_elixir(
        quote do
          alias Kernel, as: PatternKernel, warn: false

          trait :fixed, :item do
            exec :create, args_pattern: %{value: unquote(expression)}
          end
        end
      )
    end
  end

  test "match? does not hide a placeholder in its value expression" do
    for expression <- [quote(do: match?({:ok, _}, _)), quote(do: Kernel.match?({:ok, _}, _))] do
      assert_invalid_elixir(
        quote do
          trait :fixed, :item do
            exec :create, args_pattern: %{value: unquote(expression)}
          end
        end
      )
    end
  end

  test "module attributes are captured at each declaration, not at the end of the module" do
    schema =
      compile_schema(
        quote do
          @value 1
          trait :first, :item do
            exec :create, args_pattern: %{value: @value}
          end

          @value 2
          trait :second, :item do
            exec :create, args_pattern: %{value: @value}
          end
        end
      )

    ctx = SeedFactory.init(%{}, schema)
    assert SeedFactory.produce(ctx, item: [:first]).item.value == 1
    assert SeedFactory.produce(ctx, item: [:second]).item.value == 2
  end

  test "functions and matches inside a normal pattern retain their wildcards" do
    schema =
      compile_schema(
        quote do
          trait :callback, :item do
            exec :create,
              args_pattern: %{
                value: Enum.map([1, 2], fn _ -> :ok end),
                other: with({_, found} <- {:ok, 7}, do: found)
              }
          end

          trait :matched, :item do
            exec :change, args_pattern: %{value: elem({_, _} = {:ok, 8}, 1)}
          end
        end
      )

    ctx = %{} |> SeedFactory.init(schema) |> SeedFactory.produce(item: [:callback])
    assert ctx.item == %{value: [:ok, :ok], other: 7}

    ctx = SeedFactory.produce(ctx, item: [:matched])
    assert ctx.item == 8
  end

  test "with_traits references are validated when the schema is compiled" do
    for {references, error} <- [
          {[:property], ~r/requires a value/},
          {[fixed: 1], ~r/does not accept a value/},
          {[:unknown], ~r/doesn't have trait :unknown/},
          {[property: 1, property: 2], ~r/conflicting values/}
        ] do
      assert_invalid(
        error,
        quote do
          trait :property, :item do
            exec :create, args_pattern: %{value: _}
          end

          trait :fixed, :item do
            exec :create, args_pattern: %{other: true}
          end

          command :consume do
            param :input do
              param :item, entity: :item, with_traits: unquote(references)
            end

            resolve(fn args -> {:ok, %{result: args.input.item}} end)
            produce :result
          end
        end
      )
    end
  end

  test "with_traits rejects entities with no declared traits at schema compilation" do
    assert_invalid(
      ~r/entity :item has no defined traits/,
      quote do
        command :consume do
          param :item, entity: :item, with_traits: [:missing]
          resolve(fn args -> {:ok, %{result: args.item}} end)
          produce :result
        end
      end
    )
  end
end
