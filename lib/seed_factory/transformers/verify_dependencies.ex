defmodule SeedFactory.Transformers.VerifyDependencies do
  @moduledoc false
  use Spark.Dsl.Transformer

  def after?(module) do
    module in [
      SeedFactory.Transformers.IndexCommands,
      SeedFactory.Transformers.IndexEntities
    ]
  end

  def transform(dsl_state) do
    digraph = :digraph.new()
    commands = Spark.Dsl.Transformer.get_persisted(dsl_state, :commands)

    vertices =
      Map.new(commands, fn {command_name, _} ->
        vertex = :digraph.add_vertex(digraph)
        vertex = :digraph.add_vertex(digraph, vertex, command_name)

        {command_name, vertex}
      end)

    command_name_by_entity = Spark.Dsl.Transformer.get_persisted(dsl_state, :entities)

    commands
    |> Enum.each(fn {command_name, command} ->
      add_edges(command.params, digraph, vertices[command_name], vertices, command_name_by_entity)
    end)

    case :digraph_utils.cyclic_strong_components(digraph) do
      [] ->
        :digraph.delete(digraph)
        {:ok, dsl_state}

      components ->
        dependency_cycles =
          Enum.map(components, fn strong_component ->
            Enum.map(strong_component, fn vertex ->
              {_vertex, label} = :digraph.vertex(digraph, vertex)
              label
            end)
          end)

        :digraph.delete(digraph)

        formatted_cycles =
          Enum.map(dependency_cycles, fn cycle ->
            ["\n  * ", Enum.map_intersperse(cycle, " - ", &inspect/1)]
          end)

        raise Spark.Error.DslError,
          path: [:commands],
          message: "found dependency cycles:#{formatted_cycles}"
    end
  end

  def add_edges(params, digraph, vertice_to, vertices, command_name_by_entity) do
    Enum.each(params, fn {_key, parameter} ->
      case parameter.source do
        nil ->
          add_edges(parameter.params, digraph, vertice_to, vertices, command_name_by_entity)

        generator when is_function(generator, 0) ->
          :noop

        entity_name when is_atom(entity_name) ->
          required_command_name = Map.fetch!(command_name_by_entity, entity_name)
          vertice_from = Map.fetch!(vertices, required_command_name)
          :digraph.add_edge(digraph, vertice_to, vertice_from, entity_name)
      end
    end)
  end
end
