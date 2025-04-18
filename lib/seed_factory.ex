defmodule SeedFactory do
  @moduledoc """
  A toolkit for test data generation.

  The main idea of `SeedFactory` is to generate data in tests according to your application business logic (read as
  context functions if you use [Phoenix Contexts](https://hexdocs.pm/phoenix/contexts.html)) whenever it is possible
  and avoid direct inserts to the database (as opposed to `ex_machina`).
  This approach allows you to minimize testing of invalid states as you're not forced to keep complex database structure in your head in order to prepare test data.
  The library is completely agnostic to the database toolkit.

  **Context**, **entities** and **commands** are the core concepts of the library.

  Context is a `t:map/0` which can be populated with entities using commands.

  The schema with instructions on how commands modify context is described using DSL with the help of `SeedFactory.Schema` module.

  Commands can be used to:
  * produce entity (put new data in the context)
  * update entity (replace the existing entity in the context)
  * delete entity (remove the entity from the context)

  When a command is executed, produced entities are assigned to the context using the name of the entity as a key.
  A command has params with instructions on how to generate arguments for a resolver if they are not passed explicitly with `exec/3` function.
  The instruction can be specified using one of these options:
  * `:value` - any term. This option is used by default with the value of `nil`.
  * `:generate` - a zero-arity function for generating data.
  * `:entity` - an atom which points to an entity which should be taken from the context. If a required entity cannot
  be found in a context, then `SeedFactory` automatically executes a corresponding command which produces the entity.

  Entities can have traits.
  Think about them as labels which are assigned to produced/updated entities when specific commands with specific arguments are executed.

  Let's take a look at an example of a simple schema.
  ```elixir
  defmodule MyApp.SeedFactorySchema do
    use SeedFactory.Schema

    command :create_company do
      param :name, generate: &Faker.Company.name/0

      resolve(fn args ->
        with {:ok, company} <- MyApp.Companies.create_company(args) do
          {:ok, %{company: company}}
        end
      end)

      produce :company
    end

    command :create_user do
      param :name, generate: &Faker.Person.name/0
      param :role, value: :normal
      param :company, entity: :company

      resolve(fn args -> MyApp.Users.create_user(args.company, args.name, args.role) end)

      produce :user
      produce :profile
    end

    command :activate_user do
      param :user, entity: :user, with_traits: [:pending]

      resolve(fn args ->
        user = MyApp.Users.activate_user!(args.user)

        {:ok, %{user: user}}
      end)

      update :user
    end

    trait :pending, :user do
      exec :create_user
    end

    trait :active, :user do
      from :pending
      exec :activate_user
    end

    trait :admin, :user do
      exec :create_user, args_pattern: %{role: :admin}
    end

    trait :normal, :user do
      exec :create_user, args_pattern: %{role: :normal}
    end
  end
  ```
  The schema above describes how to produce 3 entities (`:company`, `:user` and `:profile`) using 2 commands (`:create_user` and `:create_company`).
  There is a third command which only updates the `:user` entity.
  There are 4 traits defined for the `:user` entity.

  To start using the schema, put metadata about it to the context using `init/2` function:
  ```elixir
  context = %{}
  context = init(context, MyApp.SeedFactorySchema)
  ```
  If you use `SeedFactory` in tests with `ExUnit`, check out `SeedFactory.Test`. This module adds initialization using `ExUnit.Callbacks.setup_all/2` callback
  and imports functions.

  Now, `exec/2` function can be used to execute a command:
  ```elixir
  context = exec(context, :create_company)
  ```
  The code above will generate arguments for `:create_company` command, execute a resolver with generated arguments and put company to context using `:company` key.
  `exec/3` can be used if you want to specify parameters explicitly:
  ```elixir
  context = exec(context, :create_company, name: "GitHub")
  ```

  Because exec function returns `t:context/0`, it is convenient to chain `exec` calls with the pipe operator:
  ```elixir
  context =
    context
    |> exec(:create_company)
    |> exec(:create_user, name: "John Doe")
  ```
  In order to get a value for the `:company` parameter of the `:create_user` command, the corresponding entity was taken from the context.
  However, it is not necessary to do so, as `SeedFactory` can automatically execute commands which produce dependent entities.
  The code above has the same effect as a single call to `:create_user` command:
  ```elixir
  context = exec(context, :create_user, name: "John Doe")
  ```

  If you're not interested in explicit providing of parameters to commands, then you can use `produce/2` function to produce
  requested entities with automatic execution of all dependent commands:
  ```elixir
  context = produce(context, :user)
  ```
  Even though `:user` is the only entity specified explicitly, `context` will have 3 new keys: `:company`, `:user` and `:profile`.

  > #### Tip {: .tip}
  > It is recommended to explicitly specify all entities in which you're interested:
  > ```elixir
  > # good
  > %{user: user} = produce(context, :user)
  >
  > # good
  > %{user: user, profile: profile} = produce(context, [:user, :profile])
  >
  > # good
  > %{user: user, company: company} = produce(context, [:user, :company])
  >
  > # bad
  > %{user: user, profile: profile, company: company} = produce(context, :user)
  > ```

  `exec/3` fails if produced entities are already present in the context.
  It is possible to rebind entities in order to assign them to the context with different names:
  ```elixir
  context =
    context
    |> rebind([user: :user1, profile: :profile1], &exec(&1, :create_user))
    |> rebind([user: :user2, profile: :profile2], &exec(&1, :create_user))
  ```
  The snippet above puts the following keys to the context: `:company`, `:user1`, `:profile1`, `:user2` and `:profile2`.
  The `:company` is shared in this case, so two users have different profiles and belong to the same company.
  A shorter counterpart using `produce/2` is the following:
  ```elixir
  context =
    context
    |> produce(user: :user1, profile: :profile1)
    |> produce(user: :user2, profile: :profile2)
  ```

  As was pointed out previously, traits are assigned to entities when commands produce/update them.
  `SeedFactory` does this automatically by tracking commands and arguments.
  You can inspect `__seed_factory_meta__` key in the context to review currently assigned traits:

  ```elixir
  context |> exec(:create_user) |> IO.inspect()
  # %{
  # __seed_factory_meta__: #SeedFactory.Meta<
  #   current_traits: %{user: [:normal, :pending]},
  #   ...
  # >,
  # ...
  # }

  context |> exec(:create_user, role: :admin) |> exec(:activate_user) |> IO.inspect()
  # %{
  # __seed_factory_meta__: #SeedFactory.Meta<
  #   current_traits: %{user: [:admin, :active]},
  #   ...
  # >,
  # ...
  # }
  ```

  The same result can be achieved by passing traits using `produce/2`:
  ```elixir
  produce(context, user: [:admin, :active])
  ```

  If you want to specify traits and assign an entity to the context with the different name, then use `:as` option:
  ```elixir
  %{active_admin: active_admin} = produce(context, user: [:admin, :active, as: :active_admin])
  ```
  """
  @type context :: map()
  @type entity_name :: atom()
  @type rebinding_rule :: {entity_name(), rebind_as :: atom()}

  @doc """
  Puts metadata about `schema` to `context`, so `context` becomes usable by other functions from this module.

  ## Example

      iex> context = %{}
      ...> init(context, MySeedFactorySchema)
      %{__seed_factory_meta__: #SeedFactory.Meta<...>}
  """
  @spec init(context(), schema :: module) :: context()
  def init(context, schema) do
    Map.put(context, :__seed_factory_meta__, SeedFactory.Meta.new(schema))
  end

  @doc """
  Changes default behaviour of entities assignment.

  Modifies a context, so commands engage with entities in the context using provided names.
  If a command requires/produces/updates/deletes an entity, the provided name will be used instead of the entity name to get value from the context or modify it.

  It helps to produce the same entity multiple times and assign it to the context with different names.

  ## Example

      # Let's assume that `:product` entity requires `:company` entity.
      # In this example we create 2 companies, `:product1` will be linked to `:company1`.
      %{company1: _, company2: _, product1: _} =
        context
        |> rebind([company: :company1, product: :product1], fn context ->
          context
          |> exec(:create_company, name: "GitHub")
          |> produce(:product)
        end)
        |> rebind([company: :company2], fn context ->
          exec(context, :create_company, name: "Microsoft")
        end)
  """
  @spec rebind(context(), [rebinding_rule()], (context() -> context())) :: context()
  def rebind(context, rebinding, callback) when is_function(callback, 1) do
    ensure_entities_exist_in_rebinding_rules!(context.__seed_factory_meta__.entities, rebinding)
    do_rebind(context, rebinding, callback)
  end

  defp ensure_entities_exist_in_rebinding_rules!(entities, rebinding) do
    for {entity_name, _rebind_as} <- rebinding do
      if not Map.has_key?(entities, entity_name) do
        raise ArgumentError, "Unknown entity #{inspect(entity_name)}"
      end
    end
  end

  defp do_rebind(context, rebinding, callback) do
    case rebinding do
      [] ->
        callback.(context)

      rebinding ->
        current_rebinding = context.__seed_factory_meta__.entities_rebinding
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

  @doc """
  Produces entities if they don't exist in the context.

  The order of specified entities doesn't matter.

  It invokes a series of commands to produce entities with specified traits.
  If the same entity can be produced by multiple commands, then the first declared command is used by default.
  In order to produce the entity using the rest of the commands use traits or `exec/3` explicitly.

  ## Examples

      # specify a single entity
      %{user: _} = produce(context, :user)

      # specify a list of entities
      %{user: _, company: _} = produce(context, [:user, :company])

      # rebind :user entity as :user1
      %{user1: _} = produce(context, user: :user1)

      # specify traits
      %{user: _} = produce(context, user: [:active, :admin])
      %{user: _} = context |> produce(user: [:pending, :admin]) |> produce(user: [:active])

      # specify traits and :as option
      %{user1: _} = produce(context, user: [:active, :admin, as: :user1])
  """
  @spec produce(
          context(),
          entity_name()
          | [
              entity_name()
              | rebinding_rule()
              | {entity_name(), [trait_name :: atom() | {:as, rebind_as :: atom()}]}
            ]
        ) :: context()
  def produce(context, entities_and_rebinding) when is_list(entities_and_rebinding) do
    {entities_with_trait_names, rebinding} = split_entities_and_rebinding(entities_and_rebinding)

    do_rebind(context, rebinding, fn context ->
      requirements =
        SeedFactory.Requirements.init()
        |> collect_requirements_for_entities_with_trait_names(
          context,
          entities_with_trait_names,
          nil,
          build_restrictions(context, entities_with_trait_names)
        )
        |> SeedFactory.Requirements.resolve_conflicts()

      lock_creation_of_dependent_entities(context, &exec_requirements(&1, requirements))
    end)
  end

  def produce(context, entity) when is_atom(entity) do
    produce(context, [entity])
  end

  @doc """
  Produces dependencies needed for specified entities.

  See `pre_exec/3` for problems it solves.

  ## Example

      # pre_produce produces a company and puts it into context,
      # so produced user1 and user2 will belong to the same company
      context = pre_produce(context, :user)
      %{user: user1} = produce(context, :user)
      %{user: user2} = produce(context, :user)
  """
  @spec pre_produce(
          context(),
          entity_name()
          | [
              entity_name()
              | rebinding_rule()
              | {entity_name(), [trait_name :: atom() | {:as, rebind_as :: atom()}]}
            ]
        ) :: context()
  def pre_produce(context, entities_and_rebinding) when is_list(entities_and_rebinding) do
    {entities_with_trait_names, rebinding} = split_entities_and_rebinding(entities_and_rebinding)

    do_rebind(context, rebinding, fn context ->
      requirements =
        SeedFactory.Requirements.init()
        |> collect_requirements_for_entities_with_trait_names(
          context,
          entities_with_trait_names,
          nil,
          build_restrictions(context, entities_with_trait_names)
        )
        |> SeedFactory.Requirements.resolve_conflicts()
        |> SeedFactory.Requirements.delete_explicitly_requested_commands()

      lock_creation_of_dependent_entities(context, &exec_requirements(&1, requirements))
    end)
  end

  def pre_produce(context, entity) when is_atom(entity) do
    pre_produce(context, [entity])
  end

  defp split_entities_and_rebinding(entities_and_rebinding) do
    Enum.map_reduce(entities_and_rebinding, [], fn
      {entity_name, rebind_as} = rebinding_rule, acc when is_atom(rebind_as) ->
        {{entity_name, []}, [rebinding_rule | acc]}

      {entity_name, list}, acc when is_list(list) ->
        {trait_names, opts} = Enum.split_while(list, &is_atom/1)

        acc =
          case opts[:as] do
            nil -> acc
            rebind_as -> [{entity_name, rebind_as} | acc]
          end

        {{entity_name, trait_names}, acc}

      entity_name, acc ->
        {{entity_name, []}, acc}
    end)
  end

  defp anything_was_produced_by_command?(context, command) do
    Enum.any?(command.producing_instructions, fn instruction ->
      binding_name = binding_name(context, instruction.entity)
      Map.has_key?(context, binding_name)
    end)
  end

  defp collect_requirements_for_command(
         requirements,
         context,
         command,
         initial_input,
         required_by,
         restrictions
       ) do
    entities_with_trait_names = parameter_requirements(command, initial_input)

    collect_requirements_for_entities_with_trait_names(
      requirements,
      context,
      entities_with_trait_names,
      required_by,
      restrictions
    )
  end

  defp collect_requirements_for_entities_with_trait_names(
         requirements,
         _context,
         entities_with_trait_names,
         _required_by,
         _restrictions
       )
       when map_size(entities_with_trait_names) == 0 do
    requirements
  end

  defp collect_requirements_for_entities_with_trait_names(
         initial_requirements,
         context,
         entities_with_trait_names,
         required_by,
         restrictions
       ) do
    {requirements, command_names} =
      Enum.reduce(
        entities_with_trait_names,
        {initial_requirements, MapSet.new()},
        fn {entity_name, trait_names}, {requirements, command_names} = acc ->
          # duplicated values are produced by parameter_requirements function after recursive calls to
          # `collect_requirements_for_command` function
          trait_names = Enum.uniq(trait_names)

          binding_name = binding_name(context, entity_name)

          if Map.has_key?(context, binding_name) do
            if trait_names == [] do
              acc
            else
              current_trait_names = current_trait_names(context, binding_name)

              absent_trait_names = trait_names -- current_trait_names

              if absent_trait_names == [] do
                acc
              else
                %{by_name: traits_by_name} = fetch_traits!(context, entity_name)

                trail =
                  context.__seed_factory_meta__.trails[binding_name] ||
                    raise """
                    Can't find trail for #{inspect(binding_name)} entity.
                    Please don't put entities that can have traits manually in the context.
                    """

                ensure_traits_not_restricted!(
                  restrictions,
                  entity_name,
                  binding_name,
                  absent_trait_names,
                  required_by
                )

                collect_requirements_for_traits(
                  acc,
                  absent_trait_names,
                  traits_by_name,
                  entity_name,
                  SeedFactory.Trail.to_map(trail),
                  required_by
                )
              end
            end
          else
            if trait_names == [] do
              command_names_that_can_produce_entity =
                fetch_command_names_by_entity_name!(context, entity_name)

              {requirements, added_command_names} =
                add_commands_to_requirements(
                  requirements,
                  command_names_that_can_produce_entity,
                  required_by,
                  []
                )

              {requirements, MapSet.union(command_names, added_command_names)}
            else
              ensure_traits_not_restricted!(
                restrictions,
                entity_name,
                binding_name,
                trait_names,
                required_by
              )

              %{by_name: traits_by_name} = fetch_traits!(context, entity_name)

              command_names_that_can_produce_entity =
                fetch_command_names_by_entity_name!(context, entity_name)

              {requirements, added_command_names} =
                add_commands_to_requirements(
                  requirements,
                  command_names_that_can_produce_entity,
                  required_by,
                  []
                )

              trait_names
              |> Enum.reduce(
                {requirements, MapSet.union(command_names, added_command_names)},
                fn trait_name, {requirements, command_names} ->
                  case Map.fetch(traits_by_name, trait_name) do
                    {:ok, traits} ->
                      command_names_to_add = Enum.map(traits, & &1.exec_step.command_name)

                      {requirements, added_command_names} =
                        add_commands_to_requirements(
                          requirements,
                          command_names_to_add,
                          required_by,
                          traits
                        )

                      {requirements, MapSet.union(command_names, MapSet.new(added_command_names))}

                    :error ->
                      raise ArgumentError,
                            "Entity #{inspect(entity_name)} doesn't have trait #{inspect(trait_name)}"
                  end
                end
              )
            end
          end
        end
      )

    Enum.reduce(command_names, requirements, fn command_name, requirements ->
      command = Map.fetch!(context.__seed_factory_meta__.commands, command_name)

      added_to_requirements_in_previous_iterations? =
        Map.has_key?(initial_requirements.commands, command_name)

      removed_from_requirements_in_current_iteration? =
        not Map.has_key?(requirements.commands, command_name)

      if added_to_requirements_in_previous_iterations? or
           removed_from_requirements_in_current_iteration? or
           anything_was_produced_by_command?(context, command) do
        requirements
      else
        collect_requirements_for_command(
          requirements,
          context,
          command,
          %{},
          command.name,
          restrictions
        )
      end
    end)
  end

  defp ensure_traits_not_restricted!(
         restrictions,
         entity_name,
         binding_name,
         trait_names_to_apply,
         required_by
       ) do
    case Map.fetch(restrictions.subsequent_traits, entity_name) do
      {:ok, subsequent_traits} ->
        intersection = intersection(trait_names_to_apply, subsequent_traits)

        if Enum.any?(intersection) do
          raise ArgumentError, """
          Cannot apply traits #{inspect(intersection)} to #{inspect(binding_name)} as a requirement for #{inspect(required_by)} command.
          The entity was requested with the following traits: #{inspect(Map.fetch!(restrictions.requested_trait_names_by_entity, entity_name))}.
          """
        end

        :ok

      :error ->
        :noop
    end
  end

  defp ensure_current_trait_names_do_not_conflict_with_required_trait_names!(
         context,
         entity_name,
         subsequent_traits,
         required_trait_names
       ) do
    binding_name = binding_name(context, entity_name)

    case context.__seed_factory_meta__.trails[binding_name] do
      nil ->
        :noop

      trail ->
        do_ensure_current_trait_names_do_not_conflict_with_required_trait_names!(
          subsequent_traits,
          required_trait_names,
          binding_name,
          current_trait_names(context, binding_name),
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
    intersection = intersection(current_trait_names, subsequent_traits)

    if Enum.any?(intersection) do
      # Generic case lists all the trait_names_to_apply, but trail analysis can provide more
      # specific information for error message
      trail_analysis =
        trail
        |> SeedFactory.Trail.to_list()
        |> Enum.find_value(fn {command_name, _added, removed} ->
          case intersection(required_trait_names, removed) do
            [] -> nil
            intersection -> {command_name, intersection}
          end
        end)

      case trail_analysis do
        nil ->
          raise ArgumentError, """
          Cannot apply traits #{inspect(required_trait_names)} to #{inspect(binding_name)}.
          There is no path from traits #{inspect(intersection)}.
          Current traits: #{inspect(current_trait_names)}.
          """

        {command_name, intersection} ->
          raise ArgumentError, """
          Cannot apply traits #{inspect(intersection)} to #{inspect(binding_name)} because they were removed by the command #{inspect(command_name)}.
          Current traits: #{inspect(current_trait_names)}.
          """
      end
    end
  end

  defp fetch_command_by_name!(context, command_name) do
    case Map.fetch(context.__seed_factory_meta__.commands, command_name) do
      {:ok, command} -> command
      :error -> raise ArgumentError, "Unknown command #{inspect(command_name)}"
    end
  end

  defp fetch_command_names_by_entity_name!(context, entity_name) do
    case Map.fetch(context.__seed_factory_meta__.entities, entity_name) do
      {:ok, command_names} -> command_names
      :error -> raise ArgumentError, "Unknown entity #{inspect(entity_name)}"
    end
  end

  defp add_commands_to_requirements(requirements, [command_name], required_by, traits) do
    {SeedFactory.Requirements.add_or_link_command(
       requirements,
       command_name,
       required_by,
       traits,
       :no_conflict
     ), MapSet.new([command_name])}
  end

  defp add_commands_to_requirements(requirements, command_names, required_by, traits) do
    # if the command can be found in requirements, and it doesn't have any conflict, it means, that it was requested
    # without ambiguity, so we can skip conflict resolution for the command
    case Enum.find(
           command_names,
           fn command_name ->
             Map.has_key?(requirements.commands, command_name) and
               not SeedFactory.Requirements.command_or_anything_in_vertical_conflicts?(
                 requirements.commands,
                 command_name
               )
           end
         ) do
      nil ->
        case SeedFactory.Requirements.analyze_conflict_group(requirements, command_names) do
          :new_group ->
            requirements =
              command_names
              |> Enum.reduce(requirements, fn command_name, requirements ->
                SeedFactory.Requirements.add_or_link_command(
                  requirements,
                  command_name,
                  required_by,
                  traits,
                  :in_conflict_group
                )
              end)
              |> SeedFactory.Requirements.add_conflict_group(command_names)

            {requirements, MapSet.new(command_names)}

          :exists ->
            requirements =
              SeedFactory.Requirements.link_commands(
                requirements,
                command_names,
                required_by,
                traits
              )

            {requirements, MapSet.new([])}

          {:is_subset, diff} ->
            requirements =
              diff
              |> Enum.reduce(requirements, &SeedFactory.Requirements.remove_command(&2, &1))
              |> SeedFactory.Requirements.link_commands(command_names, required_by, traits)

            {requirements, MapSet.new([])}

          {:contains_subset, subset} ->
            requirements =
              SeedFactory.Requirements.link_commands(requirements, subset, required_by, traits)

            {requirements, MapSet.new([])}
        end

      command_name ->
        requirements =
          SeedFactory.Requirements.link_commands(requirements, command_name, required_by, traits)

        {requirements, MapSet.new()}
    end
  end

  defp parameter_requirements(command, initial_input) do
    parameter_requirements(command.params, %{}, initial_input)
  end

  defp parameter_requirements(params, acc, initial_input) do
    Enum.reduce(params, acc, fn {key, parameter}, acc ->
      case parameter.type do
        :container ->
          parameter_requirements(parameter.params, acc, initial_input)

        :entity ->
          if Map.has_key?(initial_input, key) do
            acc
          else
            trait_names = parameter.with_traits || []
            Map.update(acc, parameter.entity, trait_names, &(trait_names ++ &1))
          end

        _ ->
          acc
      end
    end)
  end

  defp get_traits(context, entity_name) do
    context.__seed_factory_meta__.traits[entity_name]
  end

  defp fetch_traits!(context, entity_name) do
    case Map.fetch(context.__seed_factory_meta__.traits, entity_name) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "Entity #{inspect(entity_name)} doesn't have traits"
    end
  end

  defp collect_requirements_for_traits(
        acc,
        trait_names,
        traits_by_name,
        entity_name,
        trail_map,
        required_by
      ) do
    Enum.reduce(trait_names, acc, fn trait_name, acc ->
      case Map.fetch(traits_by_name, trait_name) do
        {:ok, traits} ->
          do_collect_requirements_for_traits(acc, traits, traits_by_name, trail_map, required_by)

        :error ->
          raise ArgumentError,
                "Entity #{inspect(entity_name)} doesn't have trait #{inspect(trait_name)}"
      end
    end)
  end

  defp do_collect_requirements_for_traits(
        {requirements, command_names} = acc,
        traits,
        traits_by_name,
        trail_map,
        required_by
      ) do
    Enum.find_value(traits, fn trait ->
      case trail_map[trait.exec_step.command_name] do
        nil -> nil
        data -> {trait, data}
      end
    end)
    |> case do
      nil ->
        {requirements, added_command_names} =
          add_commands_to_requirements(
            requirements,
            Enum.map(traits, & &1.exec_step.command_name),
            required_by,
            traits
          )

        acc = {requirements, MapSet.union(command_names, added_command_names)}

        Enum.reduce(traits, acc, fn trait, acc ->
          case trait.from do
            nil ->
              acc

            from when is_atom(from) ->
              do_collect_requirements_for_traits(
                acc,
                traits_by_name[from],
                traits_by_name,
                trail_map,
                required_by
              )

            from_any_of when is_list(from_any_of) ->
              if Enum.any?(from_any_of, fn from ->
                   traits = traits_by_name[from]

                   Enum.any?(traits, fn trait ->
                     data = trail_map[trait.exec_step.command_name]
                     data && trait.name in data.added
                   end)
                 end) do
                acc
              else
                from = hd(from_any_of)

                do_collect_requirements_for_traits(
                  acc,
                  traits_by_name[from],
                  traits_by_name,
                  trail_map,
                  required_by
                )
              end
          end
        end)

      {trait, %{added: added}} ->
        if trait.name in added do
          acc
        else
          label =
            case required_by do
              nil -> "specified trait"
              command_name -> "trait required by #{inspect(command_name)} command"
            end

          raise ArgumentError, """
          Traits to previously executed command #{inspect(trait.exec_step.command_name)} do not match:
            previously applied traits: #{inspect(added)}
            #{label}: #{inspect(trait.name)}
          """
        end
    end
  end

  defp squash_args(traits, initial_args \\ %{}) do
    Enum.reduce(traits, initial_args, fn trait, acc ->
      case trait.exec_step do
        %{args_pattern: nil, generate_args: nil, args_match: nil} ->
          acc

        %{args_pattern: pattern} when is_map(pattern) ->
          try do
            deep_merge_maps!(acc, pattern, [])
          catch
            {:conflict, v1, v2, path} ->
              raise ArgumentError, """
              Cannot merge arguments generated by traits for command #{inspect(trait.exec_step.command_name)}.
                Path: #{inspect(path)}
                Value 1: #{inspect(v1)}
                Value 2: #{inspect(v2)}
              """
          end

        %{generate_args: generate_args, args_match: args_match} ->
          try do
            deep_merge_maps!(acc, generate_args.(), [])
          catch
            {:conflict, _v1, _v2, _path} ->
              if args_match.(acc) do
                acc
              else
                raise ArgumentError, """
                Cannot apply trait #{inspect(trait.name)} of entity #{inspect(trait.entity)} to generated args for command #{inspect(trait.exec_step.command_name)}.
                Generated args: #{inspect(acc)}
                """
              end
          end
      end
    end)
  end

  defp deep_merge_maps!(map1, map2, path) do
    Map.merge(map1, map2, fn
      key, v1, v2 when is_map(v1) and is_map(v2) and not is_struct(v1) and not is_struct(v2) ->
        deep_merge_maps!(v1, v2, path ++ [key])

      _key, v, v ->
        v

      key, v1, v2 ->
        throw({:conflict, v1, v2, path ++ [key]})
    end)
  end

  @doc """
  Executes a command and updates the `context` according to the schema.

  ## Example

      iex> context = %{}
      ...> context = init(context, MySeedFactorySchema)
      ...> context = exec(context, :create_user, first_name: "John", last_name: "Doe")
      ...> Map.take(context.user, [:first_name, :last_name])
      %{first_name: "John", last_name: "Doe"}
  """
  @spec exec(context(), command_name :: atom(), initial_input :: map() | keyword()) :: context()
  def exec(context, command_name, initial_input \\ %{}) do
    command = fetch_command_by_name!(context, command_name)

    initial_input = Map.new(initial_input)
    context = create_dependent_entities_if_needed(context, command, initial_input)

    args = prepare_args(command.params, initial_input, context)

    case command.resolve.(args) do
      {:ok, resolver_output} when is_map(resolver_output) ->
        context
        |> exec_producing_instructions(command, resolver_output)
        |> exec_updating_instructions(command, resolver_output)
        |> exec_deleting_instructions(command)
        |> store_trails_and_sync_current_traits(command, args)

      {:error, error} ->
        raise "Unable to execute #{inspect(command_name)} command: #{inspect(error)}"
    end
  end

  @doc """
  Creates dependent entities needed for command execution.

  This is useful, when you want to execute the command multiple times reusing input entities.

  ## Example

      # Function :create_user produces multiple entities (:user and :profile), so if you want to
      # produce multiple users using a sequence of `exec` calls, you have to write this:
      %{user1: user1, user2: user2} =
        context
        |> rebind([user: :user1, profile: :profile1], &exec(&1, :create_user, role: :admin))
        |> rebind([user: :user2, profile: :profile2], &exec(&1, :create_user, role: :admin))

      # The code above is a bit wordy in a case when all we need are :user entities. We have to write
      # rebinding for :profile even though we are't interested in it.

      # A less wordy alternative is:
      context = produce(context, list_of_all_dependencies_with_their_traits)
      %{user: user1} = exec(context, :create_user, role: :admin)
      %{user: user2} = exec(context, :create_user, role: :admin)

      # However, you have to explicitly enumerate all the dependencies.
      # It can be more compact with `pre_exec` function:
      context = pre_exec(context, :create_user)
      %{user: user1} = exec(context, :create_user, role: :admin)
      %{user: user2} = exec(context, :create_user, role: :admin)
  """
  @spec pre_exec(context(), command_name :: atom(), initial_input :: map() | keyword()) ::
          context()
  def pre_exec(context, command_name, initial_input \\ %{}) do
    command = fetch_command_by_name!(context, command_name)

    initial_input = Map.new(initial_input)
    create_dependent_entities_if_needed(context, command, initial_input)
  end

  defp create_dependent_entities_if_needed(context, command, initial_input) do
    lock_creation_of_dependent_entities(context, fn context ->
      requirements =
        SeedFactory.Requirements.init()
        |> collect_requirements_for_command(
          context,
          command,
          initial_input,
          nil,
          build_restrictions(context, [])
        )
        |> SeedFactory.Requirements.resolve_conflicts()

      exec_requirements(context, requirements)
    end)
  end

  defp lock_creation_of_dependent_entities(context, callback) do
    if context.__seed_factory_meta__.create_dependent_entities? do
      context = put_meta(context, :create_dependent_entities?, false)
      context = callback.(context)

      put_meta(context, :create_dependent_entities?, true)
    else
      context
    end
  end

  defp exec_requirements(context, requirements) when requirements.commands == %{} do
    context
  end

  defp exec_requirements(context, requirements) do
    requirements
    |> SeedFactory.Requirements.deprioritize_commands_that_delete_entities_or_remove_traits(
      fn command_name -> fetch_command_by_name!(context, command_name) end,
      fn entity_name -> get_traits(context, entity_name) end
    )
    |> SeedFactory.Requirements.topologically_sorted_commands()
    |> Enum.reduce(context, fn
      command, context ->
        args = command.required_by |> Map.values() |> List.flatten() |> squash_args()
        exec(context, command.name, args)
    end)
  end

  defp traits_diff(possible_traits, args) do
    Enum.reduce(possible_traits, {[], []}, fn trait, {add, remove} = acc ->
      if args_match?(trait, args) do
        {[trait.name | add], List.wrap(trait.from) ++ remove}
      else
        acc
      end
    end)
  end

  defp possible_traits(context, entity_name, command_name) do
    List.wrap(context.__seed_factory_meta__.traits[entity_name][:by_command_name][command_name])
  end

  defp sync_current_traits(current_traits, binding_name, added_traits, removed_traits) do
    current_trait_names = current_traits[binding_name] || []
    new_trait_names = (current_trait_names -- removed_traits) ++ added_traits
    Map.put(current_traits, binding_name, new_trait_names)
  end

  defp store_trails_and_sync_current_traits(context, command, args) do
    context =
      Enum.reduce(command.producing_instructions, context, fn instruction, context ->
        binding_name = binding_name(context, instruction.entity)

        {added_traits, removed_traits} =
          context |> possible_traits(instruction.entity, command.name) |> traits_diff(args)

        trail = SeedFactory.Trail.new({command.name, added_traits, removed_traits})

        context
        |> update_meta(:trails, &Map.put(&1, binding_name, trail))
        |> update_meta(
          :current_traits,
          &sync_current_traits(&1, binding_name, added_traits, removed_traits)
        )
      end)

    context =
      Enum.reduce(command.updating_instructions, context, fn instruction, context ->
        binding_name = binding_name(context, instruction.entity)

        {added_traits, removed_traits} =
          context |> possible_traits(instruction.entity, command.name) |> traits_diff(args)

        context
        |> update_meta(:trails, fn trails ->
          Map.update!(
            trails,
            binding_name,
            &SeedFactory.Trail.add_updated_by(&1, {command.name, added_traits, removed_traits})
          )
        end)
        |> update_meta(
          :current_traits,
          &sync_current_traits(&1, binding_name, added_traits, removed_traits)
        )
      end)

    case command.deleting_instructions do
      [] ->
        context

      deleting_instructions ->
        binding_names = Enum.map(deleting_instructions, &binding_name(context, &1.entity))

        context
        |> update_meta(:trails, &Map.drop(&1, binding_names))
        |> update_meta(:current_traits, &Map.drop(&1, binding_names))
    end
  end

  defp current_trait_names(context, binding_name) do
    context.__seed_factory_meta__.current_traits[binding_name] || []
  end

  defp update_meta(context, key, callback) do
    update_in(context, [:__seed_factory_meta__, Access.key!(key)], callback)
  end

  defp put_meta(context, key, value) do
    put_in(context, [:__seed_factory_meta__, Access.key!(key)], value)
  end

  defp args_match?(%{exec_step: exec_step} = _trait, args) do
    callback = exec_step.args_match || args_pattern_to_args_match_fn(exec_step.args_pattern)
    callback.(args)
  end

  defp args_pattern_to_args_match_fn(args_pattern) do
    case args_pattern do
      nil -> fn _ -> true end
      args_pattern -> &deep_equal_maps?(args_pattern, &1)
    end
  end

  # checks whether all values from map1 are present in map2.
  defp deep_equal_maps?(map1, map2) do
    Enum.all?(map1, fn
      {key, value} when is_map(value) and not is_struct(value) ->
        deep_equal_maps?(value, map2[key])

      {key, value} ->
        map2[key] == value
    end)
  end

  defp exec_producing_instructions(context, command, resolver_output) do
    Enum.reduce(command.producing_instructions, context, fn %SeedFactory.ProducingInstruction{
                                                              entity: entity_name,
                                                              from: from
                                                            },
                                                            context ->
      binding_name = binding_name(context, entity_name)

      if Map.has_key?(context, binding_name) do
        message =
          "Cannot put entity #{inspect(entity_name)} to the context while executing #{inspect(command.name)}: key #{inspect(binding_name)} already exists"

        raise ArgumentError, message
      else
        Map.put(context, binding_name, Map.fetch!(resolver_output, from))
      end
    end)
  end

  defp exec_updating_instructions(context, command, resolver_output) do
    Enum.reduce(command.updating_instructions, context, fn %SeedFactory.UpdatingInstruction{
                                                             entity: entity_name,
                                                             from: from
                                                           },
                                                           context ->
      binding_name = binding_name(context, entity_name)

      if Map.has_key?(context, binding_name) do
        Map.put(context, binding_name, Map.fetch!(resolver_output, from))
      else
        message =
          "Cannot update entity #{inspect(entity_name)} while executing #{inspect(command.name)}: key #{inspect(binding_name)} doesn't exist in the context"

        raise ArgumentError, message
      end
    end)
  end

  defp exec_deleting_instructions(context, command) do
    Enum.reduce(command.deleting_instructions, context, fn %SeedFactory.DeletingInstruction{
                                                             entity: entity_name
                                                           },
                                                           context ->
      binding_name = binding_name(context, entity_name)

      if Map.has_key?(context, binding_name) do
        Map.delete(context, binding_name)
      else
        message =
          "Cannot delete entity #{inspect(entity_name)} from the context while executing #{inspect(command.name)}: key #{inspect(binding_name)} doesn't exist"

        raise ArgumentError, message
      end
    end)
  end

  defp binding_name(context, entity_name) do
    context.__seed_factory_meta__.entities_rebinding[entity_name] || entity_name
  end

  defp prepare_args(params, initial_input, context) do
    initial_input = Map.new(initial_input)

    ensure_args_match_defined_params!(initial_input, params)

    Map.new(params, fn
      {key, parameter} ->
        value =
          case parameter.type do
            :generator ->
              Map.get_lazy(initial_input, key, parameter.generate)

            :container ->
              prepare_args(parameter.params, Map.get(initial_input, key, %{}), context)

            :entity ->
              case Map.fetch(initial_input, key) do
                {:ok, value} ->
                  value

                :error ->
                  binding_name = binding_name(context, parameter.entity)

                  entity = Map.fetch!(context, binding_name)
                  maybe_map(entity, parameter.map)
              end

            :value ->
              Map.get(initial_input, key, parameter.value)
          end

        {key, value}
    end)
  end

  defp ensure_args_match_defined_params!(input, _params) when map_size(input) == 0, do: :noop

  defp ensure_args_match_defined_params!(input, params) do
    case Map.keys(input) -- Map.keys(params) do
      [] ->
        :noop

      keys ->
        raise ArgumentError,
              "Input doesn't match defined params. Redundant keys found: #{inspect(keys)}"
    end
  end

  defp build_restrictions(context, entities_with_trait_names) do
    requested_trait_names_by_entity = Map.new(entities_with_trait_names)

    subsequent_traits =
      requested_trait_names_by_entity
      |> Enum.flat_map(fn
        {_entity_name, []} ->
          []

        {entity_name, required_trait_names} ->
          %{by_name: traits_by_name} = fetch_traits!(context, entity_name)

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

    %{
      requested_trait_names_by_entity: requested_trait_names_by_entity,
      subsequent_traits: subsequent_traits
    }
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

  defp maybe_map(value, map) do
    if map do
      map.(value)
    else
      value
    end
  end

  defp intersection(list1, list2) do
    list1 -- (list1 -- list2)
  end
end
