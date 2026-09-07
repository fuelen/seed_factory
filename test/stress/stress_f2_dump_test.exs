defmodule SeedFactory.StressF2DumpTest do
  use ExUnit.Case, async: false
  @moduletag :stress

  # The deprioritize zone: an entity :a is put in the
  # context first, then a produce of products drawn from deleters of :a,
  # re-producers of :a, plain consumers of :a and trait consumers. Each seed
  # is built TWICE with different command names (a random tag per naming), so
  # the dump also carries a name-invariance check for the ordering pass:
  # outcomes and final entity states must not depend on command names.
  #
  #   STRESS_N=400 STRESS_OUT=<path.bin> mix test test/stress/stress_f2_dump_test.exs

  @n_cases (System.get_env("STRESS_N") || "150") |> String.to_integer()

  defp gen_schema(seed) do
    :rand.seed(:exsss, {seed * 89 + 13, seed * 97 + 7, seed * 101 + 3})

    n_deleters = Enum.random(1..2)
    n_reproducers = Enum.random(0..2)
    n_consumers = Enum.random(0..2)
    with_trait? = :rand.uniform() < 0.5

    # products p1.. assigned to each command in order
    deleters =
      Enum.map(1..n_deleters, fn i ->
        %{kind: :deleter, id: :"del#{i}", product: :"pd#{i}", param_a?: :rand.uniform() < 0.7}
      end)

    reproducers =
      Enum.map(1..n_reproducers//1, fn i ->
        %{
          kind: :reproducer,
          id: :"rep#{i}",
          product: :"pr#{i}",
          # a re-producer may also consume :a
          param_a?: :rand.uniform() < 0.3,
          extra_dep: Enum.random([nil | Enum.map(1..n_deleters, &:"pd#{&1}")])
        }
      end)

    consumers =
      Enum.map(1..n_consumers//1, fn i ->
        %{
          kind: :consumer,
          id: :"use#{i}",
          product: :"pc#{i}",
          with_trait?: with_trait? and :rand.uniform() < 0.5,
          dep_on_rep: n_reproducers > 0 and :rand.uniform() < 0.5
        }
      end)

    products =
      Enum.map(deleters, & &1.product) ++
        Enum.map(reproducers, & &1.product) ++ Enum.map(consumers, & &1.product)

    request =
      products |> Enum.shuffle() |> Enum.take(Enum.random(1..length(products)))

    %{
      deleters: deleters,
      reproducers: reproducers,
      consumers: consumers,
      with_trait?: with_trait?,
      request: request
    }
  end

  defp build_module(seed, schema, tag) do
    mod = :"Elixir.StressF2Schema#{seed}#{tag}"
    name = fn id -> :"#{tag}_#{id}" end

    deleters_code =
      Enum.map_join(schema.deleters, "\n", fn d ->
        param = if d.param_a?, do: "    param :a, entity: :a\n", else: ""

        """
          command #{inspect(name.(d.id))} do
        #{param}    resolve(fn _ -> {:ok, %{#{d.product}: #{inspect(d.product)}}} end)
            produce #{inspect(d.product)}
            delete :a
          end
        """
      end)

    reproducers_code =
      Enum.map_join(schema.reproducers, "\n", fn r ->
        param_a = if r.param_a?, do: "    param :a, entity: :a\n", else: ""

        param_dep =
          if r.extra_dep do
            "    param #{inspect(r.extra_dep)}, entity: #{inspect(r.extra_dep)}\n"
          else
            ""
          end

        """
          command #{inspect(name.(r.id))} do
        #{param_a}#{param_dep}    resolve(fn _ -> {:ok, %{a: {:re, #{inspect(r.id)}}, #{r.product}: #{inspect(r.product)}}} end)
            produce :a
            produce #{inspect(r.product)}
          end
        """
      end)

    consumers_code =
      Enum.map_join(schema.consumers, "\n", fn c ->
        wt = if c.with_trait?, do: ", with_traits: [:fresh]", else: ""

        dep =
          if c.dep_on_rep do
            rep = hd(schema.reproducers)
            "    param #{inspect(rep.product)}, entity: #{inspect(rep.product)}\n"
          else
            ""
          end

        """
          command #{inspect(name.(c.id))} do
            param :a, entity: :a#{wt}
        #{dep}    resolve(fn args -> {:ok, %{#{c.product}: args.a}} end)
            produce #{inspect(c.product)}
          end
        """
      end)

    trait_code =
      if schema.with_trait? do
        """
          trait :fresh, :a do
            exec #{inspect(name.(:create_a))}
          end
        """
      else
        ""
      end

    code = """
    defmodule #{inspect(mod)} do
      use SeedFactory.Schema

      command #{inspect(name.(:create_a))} do
        resolve(fn _ -> {:ok, %{a: :a1}} end)
        produce :a
      end

    #{deleters_code}
    #{reproducers_code}
    #{consumers_code}
    #{trait_code}
    end
    """

    Code.compile_string(code)
    {:ok, mod, code}
  rescue
    _e in Spark.Error.DslError -> :skip
  end

  defp run_naming(seed, schema, tag) do
    case build_module(seed, schema, tag) do
      :skip ->
        :skip

      {:ok, mod, source} ->
        context = SeedFactory.Context.init(%{}, mod)

        task =
          Task.async(fn ->
            try do
              context = SeedFactory.produce(context, :a)
              {:ok, SeedFactory.produce(context, schema.request)}
            rescue
              e -> {:error, e}
            end
          end)

        result =
          case Task.yield(task, 4_000) || Task.shutdown(task, :brutal_kill) do
            {:ok, r} -> r
            nil -> :timeout
          end

        outcome =
          case result do
            :timeout ->
              :hang

            {:ok, ctx} ->
              missing = Enum.reject(schema.request, &Map.has_key?(ctx, &1))

              final =
                (Map.keys(ctx) -- [:__seed_factory_meta__])
                |> Enum.sort()
                |> Enum.map(fn k -> {k, canonical_value(ctx[k])} end)

              if missing == [] do
                {:ok, final}
              else
                {:silent_missing, missing, final}
              end

            {:error, e} ->
              {:raised, e.__struct__}
          end

        {outcome, source}
    end
  end

  # command names differ between namings, so strip the tag from values
  defp canonical_value(v) when is_atom(v), do: v
  defp canonical_value({:re, id}), do: {:re, id}
  defp canonical_value(v), do: v

  test "dump outcomes" do
    out_path = System.get_env("STRESS_OUT")

    results =
      Enum.flat_map(1..@n_cases, fn seed ->
        schema = gen_schema(seed)

        case {run_naming(seed, schema, :mm), run_naming(seed, schema, :zz)} do
          {{o1, src}, {o2, _}} ->
            [
              {seed,
               %{
                 outcome: o1,
                 outcome_alt_naming: o2,
                 name_invariant: o1 == o2,
                 request: schema.request,
                 source: src
               }}
            ]

          _ ->
            []
        end
      end)

    if out_path do
      File.write!(out_path, :erlang.term_to_binary(Map.new(results)))
    end

    assert SeedFactory.StressOutcomes.alarming(results) == []
  end
end
