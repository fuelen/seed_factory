defmodule SeedFactory.Transformers.IndexTraits do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def after?(module) do
    module in [
      SeedFactory.Transformers.IndexCommands,
      SeedFactory.Transformers.IndexEntities
    ]
  end

  def transform(dsl_state) do
    traits =
      dsl_state
      |> Transformer.get_entities([:root])
      |> Enum.filter(&is_struct(&1, SeedFactory.Trait))
      |> Enum.group_by(& &1.entity)
      |> Map.new(fn {entity, traits} ->
        ensure_known_entity(entity, hd(traits), dsl_state)
        ensure_unique_names(traits, entity)
        ensure_traits_has_valid_commands(entity, traits, dsl_state)

        {entity,
         %{
           by_command_name: Enum.group_by(traits, & &1.exec_step.command_name),
           by_name: Map.new(traits, &{&1.name, &1})
         }}
      end)

    {:ok, dsl_state |> Transformer.persist(:traits, traits)}
  end

  defp ensure_known_entity(entity, trait, dsl_state) do
    command_name_by_entity = Spark.Dsl.Transformer.get_persisted(dsl_state, :entities)

    if Map.has_key?(command_name_by_entity, entity) do
      :ok
    else
      raise Spark.Error.DslError,
        path: [:root, :trait, trait.name, entity],
        message: "unknown entity"
    end
  end

  defp ensure_traits_has_valid_commands(entity, traits, dsl_state) do
    command_by_name = Spark.Dsl.Transformer.get_persisted(dsl_state, :commands)

    case Enum.find(traits, fn trait ->
           command =
             case Map.fetch(command_by_name, trait.exec_step.command_name) do
               {:ok, command} ->
                 command

               :error ->
                 raise Spark.Error.DslError,
                   path: [:root, :trait, trait.name, entity],
                   message: "unknown command #{inspect(trait.exec_step.command_name)}"
             end

           instructions = command.producing_instructions ++ command.updating_instructions
           not Enum.any?(instructions, &(&1.entity == entity))
         end) do
      nil ->
        :ok

      trait ->
        raise Spark.Error.DslError,
          path: [:root, :trait, trait.name, entity],
          message:
            "contains an exec step to the #{inspect(trait.exec_step.command_name)} command which neither produces nor updates the #{inspect(entity)} entity"
    end
  end

  defp ensure_unique_names(traits, entity) do
    traits
    |> Enum.group_by(& &1.name)
    |> Enum.each(fn
      {_trait_name, [_]} ->
        :ok

      {trait_name, [_ | _]} ->
        raise Spark.Error.DslError,
          path: [:root, :trait, trait_name, entity],
          message: "duplicated trait"
    end)
  end
end
