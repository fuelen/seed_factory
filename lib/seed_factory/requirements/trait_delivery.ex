defmodule SeedFactory.Requirements.TraitDelivery do
  @moduledoc false

  alias SeedFactory.Context
  alias SeedFactory.Params
  alias SeedFactory.Trait

  # Predicts whether the remaining steps leave every requested trait on its
  # entity, with the very args the execution will use. The only unknowns are
  # the instances of the entities the remaining steps produce or update
  # before a given step: a declaration whose firing depends on one leaves the
  # trait's verdict open. Returns the traits still open, so the caller
  # predicts them again before the next step, when more instances exist; a
  # settled trait stays settled, as the remaining steps are deterministic. A
  # certain loss raises before the first step after which the trait cannot
  # come back.
  def check!(context, steps, requested) do
    for {entity, trait_names} <- requested,
        open = Enum.filter(trait_names, &(check_trait!(context, steps, entity, &1) == :uncertain)),
        open != [],
        do: {entity, open}
  end

  defp check_trait!(context, steps, entity, trait) do
    binding_name = Context.binding_name(context, entity)
    present? = trait in Context.current_trait_names(context, binding_name)

    case predict(context, steps, entity, trait, present?) do
      :uncertain ->
        :uncertain

      {:certain, true, _remover} ->
        :certain

      {:certain, false, {:planned, command}} ->
        raise SeedFactory.MissingRequestedTraitError,
          entity: entity,
          binding: binding_name,
          trait: trait,
          removed_by: command,
          removed_when: :planned

      {:certain, false, nil} ->
        raise SeedFactory.MissingRequestedTraitError,
          entity: entity,
          binding: binding_name,
          trait: trait,
          removed_by: executed_remover(context, binding_name, trait),
          removed_when: :executed
    end
  end

  # An earlier step of this plan may have removed the trait while a later
  # re-add was still uncertain; the trail of the executed commands knows.
  defp executed_remover(context, binding_name, trait) do
    entries =
      case Context.fetch_trail(context, binding_name) do
        nil -> []
        trail -> trail |> SeedFactory.Trail.to_list() |> Enum.reverse()
      end

    entries
    |> Enum.find({nil, [], []}, fn {_command, _added, removed} -> trait in removed end)
    |> elem(0)
  end

  defp predict(context, steps, entity, trait, present?) do
    initial = {{present?, nil}, MapSet.new()}

    result =
      Enum.reduce_while(steps, initial, fn {command_name, args}, {verdict, touched} ->
        command = Context.fetch_command!(context, command_name)

        case step_effect(context, command, args, entity, trait, touched) do
          :uncertain ->
            {:halt, :uncertain}

          effect ->
            {:cont, {apply_effect(verdict, effect, command_name), touch(touched, command)}}
        end
      end)

    case result do
      :uncertain -> :uncertain
      {{present?, remover}, _touched} -> {:certain, present?, remover}
    end
  end

  # What the step does to the trait: `:add` (a sure addition settles the step
  # whatever else on it is uncertain), `:remove` (a sure removal with no
  # possible re-add), `:reset` (a fresh instance without the trait), `:none`,
  # or `:uncertain`.
  defp step_effect(context, command, args, entity, trait, touched) do
    produces? = Enum.any?(command.producing_instructions, &(&1.entity == entity))
    updates? = Enum.any?(command.updating_instructions, &(&1.entity == entity))

    if produces? or updates? do
      known_args =
        Params.known_args(command.params, args, &fetch_entity(context, touched, &1), true)

      statuses =
        for declaration <- Context.possible_traits(context, entity, command.name),
            declaration.name == trait or trait in List.wrap(declaration.from),
            do: {declaration, Trait.firing(declaration, known_args)}

      cond do
        added?(statuses, trait) -> :add
        Enum.any?(statuses, &match?({_declaration, :maybe}, &1)) -> :uncertain
        produces? -> :reset
        removed?(statuses, trait) -> :remove
        true -> :none
      end
    else
      :none
    end
  end

  defp added?(statuses, trait) do
    Enum.any?(statuses, fn {declaration, status} ->
      status == :sure and declaration.name == trait
    end)
  end

  defp removed?(statuses, trait) do
    Enum.any?(statuses, fn {declaration, status} ->
      status == :sure and trait in List.wrap(declaration.from)
    end)
  end

  defp apply_effect(verdict, :none, _command_name), do: verdict
  defp apply_effect(_verdict, :add, _command_name), do: {true, nil}
  defp apply_effect(_verdict, :reset, _command_name), do: {false, nil}
  defp apply_effect(_verdict, :remove, command_name), do: {false, {:planned, command_name}}

  defp fetch_entity(context, touched, entity) do
    if MapSet.member?(touched, entity) or not Context.entity_exists?(context, entity) do
      :unknown
    else
      {:ok, Context.fetch_entity!(context, entity)}
    end
  end

  defp touch(touched, command) do
    instructions =
      command.producing_instructions ++
        command.updating_instructions ++ command.deleting_instructions

    Enum.reduce(instructions, touched, &MapSet.put(&2, &1.entity))
  end
end
