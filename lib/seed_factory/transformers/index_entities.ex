defmodule SeedFactory.Transformers.IndexEntities do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def transform(dsl_state) do
    command_name_by_entity =
      dsl_state
      |> Transformer.get_entities([:commands])
      |> Enum.flat_map(fn command ->
        Enum.map(command.producing_instructions, fn instruction ->
          {instruction.entity, command.name}
        end)
      end)
      |> tap(&ensure_entity_can_be_produced_only_by_one_command/1)
      |> Map.new()

    {:ok, dsl_state |> Transformer.persist(:entities, command_name_by_entity)}
  end

  defp ensure_entity_can_be_produced_only_by_one_command(entities_with_command_name) do
    entities_with_command_name
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.each(fn {entity, command_names} ->
      case command_names do
        [_] ->
          :ok

        [first_command_name | rest_command_names] ->
          raise Spark.Error.DslError,
            path: [:commands, :command, hd(rest_command_names), :produce, entity],
            message:
              "only 1 command can produce the entity. Entity #{inspect(entity)} can already be produced by #{inspect(first_command_name)}"
      end
    end)
  end
end
