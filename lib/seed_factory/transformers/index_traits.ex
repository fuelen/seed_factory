defmodule SeedFactory.Transformers.IndexTraits do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def after?(module) do
    module in [
      SeedFactory.Transformers.IncludeSchemas,
      SeedFactory.Transformers.IndexCommands,
      SeedFactory.Transformers.IndexEntities
    ]
  end

  def transform(dsl_state) do
    traits_by_entity =
      dsl_state
      |> Transformer.get_persisted(:root)
      |> Enum.filter(&is_struct(&1, SeedFactory.Trait))
      |> Enum.group_by(& &1.entity)

    traits =
      traits_by_entity
      |> Map.new(fn {entity, traits} ->
        ensure_known_entity(entity, hd(traits), dsl_state)
        ensure_unique_names(traits, entity)
        ensure_traits_have_valid_commands(entity, traits, dsl_state)
        ensure_valid_from_references(entity, traits, traits_by_entity)
        traits = populate_to_field(traits)

        {entity,
         %{
           by_command_name: Enum.group_by(traits, & &1.exec_step.command_name),
           by_name: Enum.group_by(traits, & &1.name)
         }}
      end)

    {:ok, dsl_state |> Transformer.persist(:traits, traits)}
  end

  defp populate_to_field(traits) do
    from_to_mapping = Enum.group_by(traits, & &1.from, & &1.name)

    Enum.map(traits, fn trait ->
      to = from_to_mapping[trait.name] || []
      %{trait | to: to}
    end)
  end

  defp ensure_known_entity(entity, trait, dsl_state) do
    command_name_by_entity = Spark.Dsl.Transformer.get_persisted(dsl_state, :entities)

    if Map.has_key?(command_name_by_entity, entity) do
      :ok
    else
      raise Spark.Error.DslError,
        path: [:root, :trait, trait.name, entity],
        message: "unknown entity",
        location: Spark.Dsl.Entity.anno(trait)
    end
  end

  defp ensure_traits_have_valid_commands(entity, traits, dsl_state) do
    command_by_name = Spark.Dsl.Transformer.get_persisted(dsl_state, :commands)

    Enum.each(traits, fn trait ->
      command =
        case Map.fetch(command_by_name, trait.exec_step.command_name) do
          {:ok, command} ->
            command

          :error ->
            raise Spark.Error.DslError,
              path: [:root, :trait, trait.name, entity],
              message: "unknown command #{inspect(trait.exec_step.command_name)}",
              location: Spark.Dsl.Entity.anno(trait)
        end

      if trait.from == [] do
        raise Spark.Error.DslError,
          path: [:root, :trait, trait.name, entity],
          message: ":from option cannot be an empty list",
          location: Spark.Dsl.Entity.anno(trait)
      end

      transition? = not is_nil(trait.from)

      if transition? do
        produces_entity? =
          Enum.any?(command.producing_instructions, &(&1.entity == entity))

        updates_entity? =
          Enum.any?(command.updating_instructions, &(&1.entity == entity))

        cond do
          produces_entity? ->
            raise Spark.Error.DslError,
              path: [:root, :trait, trait.name, entity],
              message:
                "trait references #{inspect(command.name)} via `from`, but the command produces the #{inspect(entity)} entity. Transitions must update existing entities.",
              location: Spark.Dsl.Entity.anno(trait)

          not updates_entity? ->
            raise Spark.Error.DslError,
              path: [:root, :trait, trait.name, entity],
              message:
                "trait references #{inspect(command.name)} via `from`, but the command does not update the #{inspect(entity)} entity.",
              location: Spark.Dsl.Entity.anno(trait)

          true ->
            :ok
        end
      end

      instructions = command.producing_instructions ++ command.updating_instructions

      if not Enum.any?(instructions, &(&1.entity == entity)) do
        raise Spark.Error.DslError,
          path: [:root, :trait, trait.name, entity],
          message:
            "contains an exec step to the #{inspect(trait.exec_step.command_name)} command which neither produces nor updates the #{inspect(entity)} entity",
          location: Spark.Dsl.Entity.anno(trait)
      end
    end)
  end

  defp ensure_unique_names(traits, entity) do
    traits
    |> Enum.group_by(&{&1.name, &1.exec_step.command_name})
    |> Enum.each(fn
      {_, [_]} ->
        :ok

      {{trait_name, _command_name}, [_first, second | _rest]} ->
        raise Spark.Error.DslError,
          path: [:root, :trait, trait_name, entity],
          message: "duplicated trait",
          location: Spark.Dsl.Entity.anno(second)
    end)
  end

  defp ensure_valid_from_references(entity, traits, traits_by_entity) do
    trait_names_for_entity = MapSet.new(traits, & &1.name)

    trait_name_to_entity =
      traits_by_entity
      |> Enum.flat_map(fn {owner_entity, entity_traits} ->
        Enum.map(entity_traits, fn trait -> {trait.name, owner_entity} end)
      end)
      |> Map.new()

    Enum.each(traits, fn trait ->
      validate_from_references(trait, entity, trait_names_for_entity, trait_name_to_entity)
    end)
  end

  defp validate_from_references(%{from: nil}, _entity, _valid_trait_names, _trait_name_to_entity),
    do: :ok

  defp validate_from_references(
         %{from: from_trait_names} = trait,
         entity,
         valid_trait_names,
         trait_name_to_entity
       )
       when is_list(from_trait_names) do
    Enum.each(from_trait_names, fn from_trait_name ->
      validate_single_from_reference(
        trait,
        entity,
        from_trait_name,
        valid_trait_names,
        trait_name_to_entity
      )
    end)
  end

  defp validate_from_references(
         %{from: from_trait_name} = trait,
         entity,
         valid_trait_names,
         trait_name_to_entity
       ) do
    validate_single_from_reference(
      trait,
      entity,
      from_trait_name,
      valid_trait_names,
      trait_name_to_entity
    )
  end

  defp validate_single_from_reference(
         trait,
         entity,
         from_trait_name,
         valid_trait_names,
         trait_name_to_entity
       ) do
    cond do
      MapSet.member?(valid_trait_names, from_trait_name) ->
        :ok

      Map.has_key?(trait_name_to_entity, from_trait_name) ->
        other_entity = Map.get(trait_name_to_entity, from_trait_name)

        raise Spark.Error.DslError,
          path: [:root, :trait, trait.name, entity],
          message:
            "trait #{inspect(from_trait_name)} in `from` option belongs to entity #{inspect(other_entity)}, not #{inspect(entity)}",
          location: Spark.Dsl.Entity.anno(trait)

      true ->
        raise Spark.Error.DslError,
          path: [:root, :trait, trait.name, entity],
          message: "unknown trait #{inspect(from_trait_name)} in `from` option",
          location: Spark.Dsl.Entity.anno(trait)
    end
  end
end
