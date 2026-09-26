defmodule SeedFactory.TraitDSL do
  @moduledoc false

  # Rewrite only pattern placeholders before handing the declaration to
  # Spark. Keeping args_pattern a normal map expression preserves lexical
  # bindings, aliases, and module attributes at the declaration site.
  defmacro trait(name, entity, opts \\ []) do
    opts =
      walk_declaration(opts, fn
        {:exec, meta, [command, options]} when is_list(options) ->
          options = rewrite_option(options, name, entity, __CALLER__)
          {:exec, meta, [command, options]}

        {:args_pattern, meta, [pattern]} ->
          {:args_pattern, meta, [rewrite(pattern, name, entity, __CALLER__)]}

        node ->
          node
      end)

    quote do
      require SeedFactory.DSL.Root.Trait
      SeedFactory.DSL.Root.Trait.trait(unquote(name), unquote(entity), unquote(opts))
    end
  end

  # Quoted DSL-looking calls are data, not declarations of this schema.
  defp walk_declaration({:quote, _, _} = node, _fun), do: node

  defp walk_declaration(node, fun) do
    case fun.(node) do
      tuple when is_tuple(tuple) ->
        tuple |> Tuple.to_list() |> Enum.map(&walk_declaration(&1, fun)) |> List.to_tuple()

      list when is_list(list) ->
        Enum.map(list, &walk_declaration(&1, fun))

      other ->
        other
    end
  end

  defp rewrite_option(options, name, entity, env) do
    case Keyword.fetch(options, :args_pattern) do
      {:ok, pattern} -> Keyword.put(options, :args_pattern, rewrite(pattern, name, entity, env))
      :error -> options
    end
  end

  defp rewrite(pattern, name, entity, env) do
    {pattern, count} = replace_values(pattern)

    if count > 1 do
      raise Spark.Error.DslError,
        module: env.module,
        path: [:root, :trait, name, entity],
        message: "args_pattern supports exactly one _ placeholder",
        location: :erl_anno.new(env.line)
    end

    pattern
  end

  # Only literal map values belong to this DSL. Leave all other expressions,
  # including their underscores, for Elixir and the caller's macros to compile.
  defp replace_values({:%{}, meta, pairs}) do
    {pairs, count} =
      Enum.map_reduce(pairs, 0, fn
        {key, {:_, _, context}}, count when is_atom(context) ->
          {{key, Macro.escape(SeedFactory.Trait.placeholder())}, count + 1}

        {key, value}, count ->
          {value, nested_count} = replace_values(value)
          {{key, value}, count + nested_count}

        other, count ->
          {other, count}
      end)

    {{:%{}, meta, pairs}, count}
  end

  defp replace_values(other), do: {other, 0}
end
