defmodule SeedFactory.Requirements.TraitDelivery do
  @moduledoc false

  alias SeedFactory.Context
  alias SeedFactory.Params
  alias SeedFactory.Trait

  # Predicts whether the remaining steps leave every required trait on its
  # entity by the time its consumer runs, with the very args the execution
  # will use. A requirement is `{entity, trait_names, consumer}`: the consumer
  # is a planned command reading the entity through a parameter, or nil for
  # the request, which reads it at the end of the plan. The only unknowns are
  # the instances of the entities the remaining steps produce or update
  # before a given step: a declaration whose firing depends on one leaves the
  # trait's verdict open. Returns the requirements still open, so the caller
  # predicts them again before the next step, when more instances exist; a
  # settled trait stays settled, as the remaining steps are deterministic. A
  # certain loss raises before the first step after which the trait cannot
  # come back.
  # `{:any, entity, trait_names, consumer}` requires at least one source of
  # a transition, rather than every trait in the list.
  def check!(context, steps, required) do
    Enum.flat_map(required, fn
      {:any, entity, trait_names, consumer} = requirement ->
        preceding = steps_before(steps, consumer)

        case check_any!(context, preceding, entity, trait_names, consumer) do
          :certain -> []
          :uncertain -> [requirement]
        end

      {entity, trait_names, consumer} ->
        preceding = steps_before(steps, consumer)

        case Enum.filter(
               trait_names,
               &(check_trait!(context, preceding, entity, &1, consumer) == :uncertain)
             ) do
          [] -> []
          open -> [{entity, open, consumer}]
        end
    end)
  end

  defp check_any!(context, steps, entity, traits, consumer) do
    binding = Context.binding_name(context, entity)
    current = Context.current_trait_names(context, binding)

    verdicts = Enum.map(traits, &predict(context, steps, entity, &1, &1 in current))

    cond do
      Enum.any?(verdicts, &match?({:certain, true, _}, &1)) ->
        :certain

      :uncertain in verdicts ->
        :uncertain

      true ->
        {removed_by, removed_when, removed_trait} = remover(context, binding, traits, verdicts)

        raise SeedFactory.MissingRequestedTraitError,
          entity: entity,
          binding: binding,
          trait: traits,
          required_by: consumer,
          removed_by: removed_by,
          removed_when: removed_when,
          removed_trait: removed_trait
    end
  end

  # A source is never parameterized, so a step can only remove it outright.
  defp remover(context, binding, traits, verdicts) do
    planned =
      Enum.find_value(Enum.zip(traits, verdicts), fn
        {trait, {:certain, false, {:planned, command}}} -> {command, :planned, trait}
        {_trait, {:certain, false, nil}} -> nil
      end)

    planned ||
      Enum.find_value(traits, {nil, :planned, nil}, fn trait ->
        case executed_remover(context, binding, trait) do
          nil -> nil
          command -> {command, :executed, trait}
        end
      end)
  end

  defp steps_before(steps, nil), do: steps

  defp steps_before(steps, consumer) do
    Enum.take_while(steps, fn {command_name, _args} -> command_name != consumer end)
  end

  defp check_trait!(context, steps, entity, trait, consumer) do
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
          required_by: consumer,
          removed_by: command,
          removed_when: :planned

      {:certain, false, {:assigned, command, value}} ->
        raise SeedFactory.MissingRequestedTraitError,
          entity: entity,
          binding: binding_name,
          trait: trait,
          required_by: consumer,
          removed_by: command,
          removed_when: :assigned,
          assigned_value: value

      {:certain, false, nil} ->
        raise SeedFactory.MissingRequestedTraitError,
          entity: entity,
          binding: binding_name,
          trait: trait,
          required_by: consumer,
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
  # or `:uncertain`. A removal or reset carries `{:ok, value}` when the step
  # assigns another value to the requested parameterized trait.
  defp step_effect(context, command, args, entity, trait, touched) do
    produces? = Enum.any?(command.producing_instructions, &(&1.entity == entity))
    updates? = Enum.any?(command.updating_instructions, &(&1.entity == entity))

    if produces? or updates? do
      known_args =
        Params.known_args(command.params, args, &fetch_entity(context, touched, &1), true)

      declarations = Context.possible_traits(context, entity, command.name)

      effect =
        Enum.reduce_while(declarations, :none, fn declaration, effect ->
          concrete = Trait.for_reference(declaration, trait)

          addition =
            if concrete.name == trait do
              Trait.firing(concrete, known_args)
            else
              :cannot
            end

          if addition == :sure do
            {:halt, :add}
          else
            removal = Trait.removal_firing(declaration, trait, known_args, addition)

            effect =
              cond do
                effect == :uncertain or addition == :maybe or removal == :maybe -> :uncertain
                removal == :sure -> :remove
                true -> effect
              end

            {:cont, effect}
          end
        end)

      cond do
        effect in [:add, :uncertain] ->
          effect

        produces? ->
          {:reset, Enum.find_value(declarations, &Trait.assigned_value(&1, trait, known_args))}

        effect == :remove ->
          {:remove, Enum.find_value(declarations, &Trait.assigned_value(&1, trait, known_args))}

        true ->
          :none
      end
    else
      :none
    end
  end

  defp apply_effect(verdict, :none, _command_name), do: verdict
  defp apply_effect(_verdict, :add, _command_name), do: {true, nil}
  defp apply_effect(_verdict, {:reset, nil}, _command_name), do: {false, nil}
  defp apply_effect(_verdict, {:remove, nil}, command_name), do: {false, {:planned, command_name}}

  defp apply_effect(_verdict, {_effect, {:ok, value}}, command_name) do
    {false, {:assigned, command_name, value}}
  end

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
