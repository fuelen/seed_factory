defmodule SeedFactory.Transformers.VerifyDependencies do
  @moduledoc false
  use Spark.Dsl.Transformer

  # TODO: migrate to libgraph once this issue is solved
  # https://github.com/bitwalker/libgraph/issues/56

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

    command_names_by_entity = Spark.Dsl.Transformer.get_persisted(dsl_state, :entities)

    Enum.each(commands, fn {command_name, command} ->
      case add_edges(
             command.params,
             digraph,
             vertices[command_name],
             vertices,
             command_names_by_entity
           ) do
        :ok ->
          :ok

        {:error, :unknown_entity, param_name, entity_name} ->
          raise Spark.Error.DslError,
            path: [:root, :command, command.name],
            message:
              "param #{inspect(param_name)} references unknown entity #{inspect(entity_name)}",
            location: Spark.Dsl.Entity.anno(command)
      end
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
          path: [:root],
          message: "found dependency cycles:#{formatted_cycles}"
    end
  end

  defp add_edges(params, digraph, vertice_to, vertices, command_names_by_entity) do
    Enum.reduce_while(params, :ok, fn {_key, parameter}, :ok ->
      case parameter.type do
        :container ->
          case add_edges(parameter.params, digraph, vertice_to, vertices, command_names_by_entity) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end

        :entity ->
          case Map.fetch(command_names_by_entity, parameter.entity) do
            {:ok, [required_command_name | _]} ->
              vertice_from = Map.fetch!(vertices, required_command_name)
              :digraph.add_edge(digraph, vertice_to, vertice_from, parameter.entity)
              {:cont, :ok}

            :error ->
              {:halt, {:error, :unknown_entity, parameter.name, parameter.entity}}
          end

        _ ->
          {:cont, :ok}
      end
    end)
  end
end
