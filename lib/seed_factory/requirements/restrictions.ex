defmodule SeedFactory.Requirements.Restrictions do
  @moduledoc false

  @enforce_keys [:requested_trait_names_by_entity, :subsequent_traits]
  defstruct [:requested_trait_names_by_entity, :subsequent_traits]

  def new(context, entities_with_trait_names) do
    requested_trait_names_by_entity = Map.new(entities_with_trait_names)

    subsequent_traits =
      requested_trait_names_by_entity
      |> Enum.flat_map(fn
        {_entity_name, []} ->
          []

        {entity_name, required_trait_names} ->
          %{by_name: traits_by_name} = SeedFactory.Context.fetch_traits!(context, entity_name)

          subsequent_traits = scan_subsequent_traits(required_trait_names, traits_by_name)

          if subsequent_traits == [] do
            []
          else
            ensure_current_trait_names_do_not_conflict_with_required_trait_names!(
              context,
              entity_name,
              subsequent_traits,
              required_trait_names
            )

            [{entity_name, subsequent_traits}]
          end
      end)
      |> Map.new()

    %__MODULE__{
      requested_trait_names_by_entity: requested_trait_names_by_entity,
      subsequent_traits: subsequent_traits
    }
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
          subsequent_traits,
          required_trait_names,
          binding_name,
          SeedFactory.Context.current_trait_names(context, binding_name),
          trail
        )
    end
  end

  defp do_ensure_current_trait_names_do_not_conflict_with_required_trait_names!(
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
            binding: binding_name,
            required_traits: required_trait_names,
            conflicting_traits: intersection,
            current_traits: current_trait_names

        {command_name, removed_traits} ->
          raise SeedFactory.TraitRemovedByCommandError,
            binding: binding_name,
            removed_traits: removed_traits,
            command: command_name,
            current_traits: current_trait_names
      end
    end
  end
end
