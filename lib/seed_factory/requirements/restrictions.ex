defmodule SeedFactory.Requirements.Restrictions do
  @moduledoc false

  @enforce_keys [
    :requested_trait_names_by_entity,
    :subsequent_traits,
    :command_names_and_traits_by_entity
  ]
  defstruct [
    :requested_trait_names_by_entity,
    :subsequent_traits,
    :command_names_and_traits_by_entity
  ]

  def new(context, entities_with_trait_names) do
    requested_trait_names_by_entity = Map.new(entities_with_trait_names)

    {requested_traits, subsequent_traits} =
      requested_trait_names_by_entity
      |> Enum.flat_map_reduce([], fn
        {_entity_name, []}, acc ->
          {[], acc}

        {entity_name, required_trait_names}, acc ->
          %{by_name: traits_by_name} = SeedFactory.Context.fetch_traits!(context, entity_name)

          traits = fetch_traits!(traits_by_name, required_trait_names, entity_name)

          subsequent_traits = scan_subsequent_traits(required_trait_names, traits_by_name)

          acc =
            if subsequent_traits == [] do
              acc
            else
              ensure_current_trait_names_do_not_conflict_with_required_trait_names!(
                context,
                entity_name,
                subsequent_traits,
                required_trait_names
              )

              [{entity_name, subsequent_traits} | acc]
            end

          {traits, acc}
      end)

    command_names_and_traits_by_entity =
      build_command_names_and_traits_by_entity(context, requested_traits)

    validate_no_conflicting_traits!(
      command_names_and_traits_by_entity,
      requested_trait_names_by_entity
    )

    %__MODULE__{
      requested_trait_names_by_entity: requested_trait_names_by_entity,
      subsequent_traits: Map.new(subsequent_traits),
      command_names_and_traits_by_entity: command_names_and_traits_by_entity
    }
  end

  defp validate_no_conflicting_traits!(
         command_names_and_traits_by_entity,
         requested_trait_names_by_entity
       ) do
    # Only check entities that were NOT explicitly requested with traits.
    # If an entity is explicitly requested, its traits take priority over side effects.
    entities_to_check =
      Map.drop(command_names_and_traits_by_entity, Map.keys(requested_trait_names_by_entity))

    conflicts =
      Enum.flat_map(entities_to_check, fn
        {_entity, {[_single_command], _traits}} ->
          []

        {entity, {_command_names, traits}} ->
          source_entities = traits |> Enum.map(& &1.entity) |> Enum.uniq()

          if match?([_, _ | _], source_entities) do
            [{entity, Enum.group_by(traits, & &1.exec_step.command_name)}]
          else
            []
          end
      end)

    if conflicts != [] do
      raise SeedFactory.ConflictingTraitsError, conflicts: conflicts
    end
  end

  defp build_command_names_and_traits_by_entity(context, requested_traits) do
    requested_traits
    |> Enum.flat_map(fn trait ->
      command = SeedFactory.Context.fetch_command!(context, trait.exec_step.command_name)

      Enum.map(command.producing_instructions, fn instruction ->
        {instruction.entity, trait}
      end)
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {entity_name, traits} ->
      command_names = traits |> Enum.map(& &1.exec_step.command_name) |> Enum.uniq()
      {entity_name, {command_names, traits}}
    end)
  end

  defp fetch_traits!(traits_by_name, trait_names, entity_name) do
    Enum.flat_map(trait_names, fn trait_name ->
      case Map.fetch(traits_by_name, trait_name) do
        {:ok, traits} ->
          traits

        :error ->
          raise SeedFactory.UnknownTraitError,
            entity: entity_name,
            trait: trait_name,
            available: Map.keys(traits_by_name)
      end
    end)
  end

  def command_names_and_traits_for_entity(%__MODULE__{} = restrictions, context, entity_name) do
    case restrictions.command_names_and_traits_by_entity[entity_name] do
      {_command_names, _traits} = result ->
        result

      nil ->
        {SeedFactory.Context.fetch_command_names_by_entity!(context, entity_name), []}
    end
  end

  def ensure_not_restricted!(
        %__MODULE__{} = restrictions,
        entity_name,
        binding_name,
        trait_names_to_apply,
        required_by
      ) do
    case Map.fetch(restrictions.subsequent_traits, entity_name) do
      {:ok, subsequent_traits} ->
        intersection = SeedFactory.ListUtils.intersection(trait_names_to_apply, subsequent_traits)

        if Enum.any?(intersection) do
          raise SeedFactory.TraitRestrictionConflictError,
            entity: entity_name,
            binding: binding_name,
            traits: intersection,
            required_by: required_by,
            requested_traits:
              Map.fetch!(restrictions.requested_trait_names_by_entity, entity_name)
        end

        :ok

      :error ->
        :noop
    end
  end

  defp scan_subsequent_traits(trait_names, traits_by_name) do
    Enum.uniq(scan_subsequent_traits(trait_names, traits_by_name, []))
  end

  defp scan_subsequent_traits([], _traits_by_name, acc) do
    acc
  end

  defp scan_subsequent_traits(trait_names, traits_by_name, acc) do
    subsequent_trait_names =
      traits_by_name
      |> Map.take(trait_names)
      |> Enum.flat_map(&elem(&1, 1))
      |> Enum.flat_map(& &1.to)

    acc = acc ++ subsequent_trait_names
    scan_subsequent_traits(subsequent_trait_names, traits_by_name, acc)
  end

  defp ensure_current_trait_names_do_not_conflict_with_required_trait_names!(
         context,
         entity_name,
         subsequent_traits,
         required_trait_names
       ) do
    binding_name = SeedFactory.Context.binding_name(context, entity_name)

    case SeedFactory.Context.fetch_trail(context, binding_name) do
      nil ->
        :noop

      trail ->
        do_ensure_current_trait_names_do_not_conflict_with_required_trait_names!(
          entity_name,
          subsequent_traits,
          required_trait_names,
          binding_name,
          SeedFactory.Context.current_trait_names(context, binding_name),
          trail
        )
    end
  end

  defp do_ensure_current_trait_names_do_not_conflict_with_required_trait_names!(
         entity_name,
         subsequent_traits,
         required_trait_names,
         binding_name,
         current_trait_names,
         trail
       ) do
    intersection = SeedFactory.ListUtils.intersection(current_trait_names, subsequent_traits)

    if Enum.any?(intersection) do
      trail_analysis =
        trail
        |> SeedFactory.Trail.to_list()
        |> Enum.find_value(fn {command_name, _added, removed} ->
          case SeedFactory.ListUtils.intersection(required_trait_names, removed) do
            [] -> nil
            intersection -> {command_name, intersection}
          end
        end)

      case trail_analysis do
        nil ->
          raise SeedFactory.TraitPathNotFoundError,
            entity: entity_name,
            binding: binding_name,
            required_traits: required_trait_names,
            conflicting_traits: intersection,
            current_traits: current_trait_names

        {command_name, removed_traits} ->
          raise SeedFactory.TraitRemovedByCommandError,
            entity: entity_name,
            binding: binding_name,
            removed_traits: removed_traits,
            command: command_name,
            current_traits: current_trait_names
      end
    end
  end
end
