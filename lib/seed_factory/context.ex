defmodule SeedFactory.Context do
  @moduledoc false

  def init(context, schema) when is_map(context) and is_atom(schema) do
    Map.put(context, :__seed_factory_meta__, SeedFactory.Meta.new(schema))
  end

  def binding_name(context, entity_name) do
    context.__seed_factory_meta__.entities_rebinding[entity_name] || entity_name
  end

  defp entity_defined_in_schema?(context, entity_name) do
    Map.has_key?(context.__seed_factory_meta__.entities, entity_name)
  end

  def entity_exists?(context, entity_name) do
    binding_name = binding_name(context, entity_name)
    Map.has_key?(context, binding_name)
  end

  defp get_entities_rebinding(context) do
    context.__seed_factory_meta__.entities_rebinding
  end

  defp create_dependent_entities?(context) do
    context.__seed_factory_meta__.create_dependent_entities?
  end

  def lock_creation_of_dependent_entities(context, callback) when is_function(callback, 1) do
    if create_dependent_entities?(context) do
      context
      |> put_meta(:create_dependent_entities?, false)
      |> callback.()
      |> put_meta(:create_dependent_entities?, true)
    else
      context
    end
  end

  def fetch_entity!(context, entity_name) do
    binding_name = binding_name(context, entity_name)
    Map.fetch!(context, binding_name)
  end

  def current_trait_names(context, binding_name) do
    context.__seed_factory_meta__.current_traits[binding_name] || []
  end

  def get_traits(context, entity_name) do
    context.__seed_factory_meta__.traits[entity_name]
  end

  defp possible_traits(context, entity_name, command_name) do
    List.wrap(context.__seed_factory_meta__.traits[entity_name][:by_command_name][command_name])
  end

  def fetch_traits!(context, entity_name) do
    case Map.fetch(context.__seed_factory_meta__.traits, entity_name) do
      {:ok, value} -> value
      :error -> raise SeedFactory.TraitNotFoundError, entity: entity_name
    end
  end

  def fetch_command!(context, command_name) do
    case Map.fetch(context.__seed_factory_meta__.commands, command_name) do
      {:ok, command} ->
        command

      :error ->
        raise SeedFactory.UnknownCommandError,
          command: command_name,
          available: Map.keys(context.__seed_factory_meta__.commands)
    end
  end

  def fetch_trail(context, binding_name) do
    context.__seed_factory_meta__.trails[binding_name]
  end

  def fetch_command_names_by_entity!(context, entity_name) do
    case Map.fetch(context.__seed_factory_meta__.entities, entity_name) do
      {:ok, command_names} ->
        command_names

      :error ->
        raise SeedFactory.UnknownEntityError,
          entity: entity_name,
          available: Map.keys(context.__seed_factory_meta__.entities)
    end
  end

  defp update_meta(context, key, callback) do
    update_in(context, [:__seed_factory_meta__, Access.key!(key)], callback)
  end

  defp put_meta(context, key, value) do
    put_in(context, [:__seed_factory_meta__, Access.key!(key)], value)
  end

  defp put_entity_new!(context, entity_name, value, command_name) do
    binding_name = binding_name(context, entity_name)

    if Map.has_key?(context, binding_name) do
      current_traits = current_trait_names(context, binding_name)

      raise SeedFactory.EntityAlreadyExistsError,
        entity: entity_name,
        binding: binding_name,
        command: command_name,
        traits: current_traits
    else
      Map.put(context, binding_name, value)
    end
  end

  defp update_entity!(context, entity_name, value, command_name) do
    binding_name = binding_name(context, entity_name)

    if Map.has_key?(context, binding_name) do
      Map.put(context, binding_name, value)
    else
      raise SeedFactory.EntityNotFoundError,
        entity: entity_name,
        binding: binding_name,
        command: command_name,
        operation: :update
    end
  end

  defp delete_entity!(context, entity_name, command_name) do
    binding_name = binding_name(context, entity_name)

    if Map.has_key?(context, binding_name) do
      Map.delete(context, binding_name)
    else
      raise SeedFactory.EntityNotFoundError,
        entity: entity_name,
        binding: binding_name,
        command: command_name,
        operation: :delete
    end
  end

  def rebind(context, rebinding, callback) when is_function(callback, 1) do
    ensure_entities_exist_in_rebinding!(context, rebinding)
    do_rebind(context, rebinding, callback)
  end

  defp ensure_entities_exist_in_rebinding!(context, rebinding) do
    for {entity_name, _rebind_as} <- rebinding do
      if not entity_defined_in_schema?(context, entity_name) do
        raise SeedFactory.UnknownEntityError,
          entity: entity_name,
          available: Map.keys(context.__seed_factory_meta__.entities)
      end
    end
  end

  defp do_rebind(context, rebinding, callback) do
    case rebinding do
      [] ->
        callback.(context)

      rebinding ->
        current_rebinding = get_entities_rebinding(context)
        new_rebinding = merge_rebinding!(current_rebinding, Map.new(rebinding))

        context
        |> put_meta(:entities_rebinding, new_rebinding)
        |> callback.()
        |> put_meta(:entities_rebinding, current_rebinding)
    end
  end

  defp merge_rebinding!(current_rebinding, new_rebinding) do
    Map.merge(
      current_rebinding,
      new_rebinding,
      fn
        _key, v, v ->
          v

        key, v1, v2 ->
          raise ArgumentError,
                "Rebinding conflict. Cannot rebind `#{inspect(key)}` to `#{inspect(v2)}`. Current value `#{inspect(v1)}`."
      end
    )
  end

  def store_trails_and_sync_current_traits(context, command, args) do
    context =
      Enum.reduce(command.producing_instructions, context, fn instruction, context ->
        binding_name = binding_name(context, instruction.entity)

        {added_traits, []} =
          context
          |> possible_traits(instruction.entity, command.name)
          |> SeedFactory.Trait.resolve_changes(args)

        trail = SeedFactory.Trail.new({command.name, added_traits, []})

        context
        |> update_meta(:trails, &Map.put(&1, binding_name, trail))
        |> update_meta(:current_traits, &Map.put(&1, binding_name, added_traits))
      end)

    context =
      Enum.reduce(command.updating_instructions, context, fn instruction, context ->
        binding_name = binding_name(context, instruction.entity)
        current_trait_names = current_trait_names(context, binding_name)

        {traits_to_add, traits_to_remove} =
          context
          |> possible_traits(instruction.entity, command.name)
          |> SeedFactory.Trait.resolve_changes(args)

        traits_to_remove =
          SeedFactory.ListUtils.intersection(current_trait_names, traits_to_remove)

        new_trait_names = (current_trait_names -- traits_to_remove) ++ traits_to_add

        context
        |> update_meta(:trails, fn trails ->
          Map.update!(
            trails,
            binding_name,
            &SeedFactory.Trail.add_updated_by(&1, {command.name, traits_to_add, traits_to_remove})
          )
        end)
        |> update_meta(:current_traits, &Map.put(&1, binding_name, new_trait_names))
      end)

    case command.deleting_instructions do
      [] ->
        context

      deleting_instructions ->
        binding_names =
          Enum.map(deleting_instructions, &binding_name(context, &1.entity))

        context
        |> update_meta(:trails, &Map.drop(&1, binding_names))
        |> update_meta(:current_traits, &Map.drop(&1, binding_names))
    end
  end

  def exec_producing_instructions(context, command, resolver_output) do
    Enum.reduce(command.producing_instructions, context, fn %SeedFactory.ProducingInstruction{
                                                              entity: entity_name,
                                                              from: from
                                                            },
                                                            context ->
      value = Map.fetch!(resolver_output, from)
      put_entity_new!(context, entity_name, value, command.name)
    end)
  end

  def exec_updating_instructions(context, command, resolver_output) do
    Enum.reduce(command.updating_instructions, context, fn %SeedFactory.UpdatingInstruction{
                                                             entity: entity_name,
                                                             from: from
                                                           },
                                                           context ->
      value = Map.fetch!(resolver_output, from)
      update_entity!(context, entity_name, value, command.name)
    end)
  end

  def exec_deleting_instructions(context, command) do
    Enum.reduce(command.deleting_instructions, context, fn %SeedFactory.DeletingInstruction{
                                                             entity: entity_name
                                                           },
                                                           context ->
      delete_entity!(context, entity_name, command.name)
    end)
  end
end
