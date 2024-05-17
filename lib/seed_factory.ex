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
  > It is recommended to explicitly specify all entities in which you're insterested:
  > ```elixir
  > # good
  > %{user: user} = produce(contex, :user)
  >
  > # good
  > %{user: user, profile: profile} = produce(contex, [:user, :profile])
  >
  > # good
  > %{user: user, company: company} = produce(contex, [:user, :company])
  >
  > # bad
  > %{user: user, profile: profile, company: company} = produce(contex, :user)
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

      # specify a list of entitities
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
        init_requirements()
        |> collect_requirements_for_entities_with_trait_names(
          context,
          entities_with_trait_names,
          nil,
          build_restrictions(context, entities_with_trait_names)
        )
        |> resolve_conflicts()

      lock_creation_of_dependent_entities(context, &exec_requirements(requirements, &1))
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
        init_requirements()
        |> collect_requirements_for_entities_with_trait_names(
          context,
          entities_with_trait_names,
          nil,
          build_restrictions(context, entities_with_trait_names)
        )
        |> resolve_conflicts()
        |> delete_requirements_which_are_requested_explicitly()

      lock_creation_of_dependent_entities(context, &exec_requirements(requirements, &1))
    end)
  end

  def pre_produce(context, entity) when is_atom(entity) do
    pre_produce(context, [entity])
  end

  defp delete_requirements_which_are_requested_explicitly(requirements) do
    Enum.reduce(requirements.commands, requirements, fn {command_name, data}, acc ->
      if requested_explicitly?(data) do
        delete_requirement(acc, command_name)
      else
        acc
      end
    end)
  end

  defp requested_explicitly?(data) do
    nil in data.required_by
  end

  defp delete_requirement(requirements, command_name_to_delete) do
    case requirements.commands[command_name_to_delete] do
      nil ->
        requirements

      data ->
        Enum.reduce(
          data.required_by,
          %{requirements | commands: Map.delete(requirements.commands, command_name_to_delete)},
          &delete_requirement(&2, &1)
        )
    end
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
         _limitations
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
                %{by_name: trait_by_name} = fetch_traits!(context, entity_name)

                trail =
                  context.__seed_factory_meta__.trails[binding_name] ||
                    raise """
                    Can't find trail for #{inspect(binding_name)} entity.
                    Please don't put entities that can have traits manually in the context.
                    """

                currently_executed =
                  if current_trait_names == [] do
                    %{trail.produced_by => %{}}
                  else
                    current_trait_names
                    |> select_traits_with_dependencies_by_names(
                      trait_by_name,
                      entity_name,
                      trail
                    )
                    |> ensure_no_restrictions!(restrictions, entity_name, :current)
                    |> executed_commands_from_traits()
                  end

                absent_trait_names
                |> select_traits_with_dependencies_by_names(
                  trait_by_name,
                  entity_name,
                  context.__seed_factory_meta__.trails[entity_name]
                )
                |> Enum.group_by(& &1.exec_step.command_name)
                |> Enum.reduce(acc, fn {command_name, traits},
                                       {requirements, command_names} = acc ->
                  case currently_executed[command_name] do
                    nil ->
                      {add_non_conflicting_command_to_requirements(
                         requirements,
                         command_name,
                         required_by,
                         traits
                       ), MapSet.put(command_names, command_name)}

                    already_applied_args ->
                      args = squash_args(traits)

                      if deep_equal_maps?(args, already_applied_args) do
                        acc
                      else
                        raise ArgumentError, """
                        Args to previously executed command #{inspect(command_name)} do not match:
                          args from previously applied traits: #{inspect(already_applied_args)}
                          args for specified traits: #{inspect(args)}
                        """
                      end
                  end
                end)
              end
            end
          else
            if trait_names == [] do
              restrictions.traits
              |> Enum.filter(fn trait ->
                context
                |> fetch_command_by_name!(trait.exec_step.command_name)
                |> command_produces?(entity_name)
              end)
              |> Enum.group_by(& &1.exec_step.command_name)
              |> Enum.to_list()
              |> case do
                [] ->
                  command_names_that_can_produce_entity =
                    fetch_command_names_by_entity_name!(context, entity_name)

                  {requirements, added_command_names} =
                    add_conflicting_commands_to_requirements(
                      requirements,
                      command_names_that_can_produce_entity,
                      required_by
                    )

                  {requirements, MapSet.union(command_names, added_command_names)}

                [{command_name, traits}] ->
                  {add_non_conflicting_command_to_requirements(
                     requirements,
                     command_name,
                     required_by,
                     traits
                   ), MapSet.put(command_names, command_name)}
              end
            else
              %{by_name: trait_by_name} = fetch_traits!(context, entity_name)

              {acc, _} =
                trait_names
                |> select_traits_with_dependencies_by_names(
                  trait_by_name,
                  entity_name,
                  context.__seed_factory_meta__.trails[entity_name]
                )
                |> ensure_no_restrictions!(restrictions, entity_name, :new)
                |> Enum.reduce({acc, nil}, fn trait,
                                              {{requirements, command_names},
                                               previous_command_name} ->
                  dependency_for_previous_trait? = trait.name not in trait_names

                  required_by =
                    if dependency_for_previous_trait? do
                      previous_command_name
                    else
                      required_by
                    end

                  command_name = trait.exec_step.command_name

                  {{add_non_conflicting_command_to_requirements(
                      requirements,
                      command_name,
                      required_by,
                      [trait]
                    ), MapSet.put(command_names, command_name)}, command_name}
                end)

              acc
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

  defp command_produces?(command, entity_name) do
    Enum.any?(command.producing_instructions, fn instruction ->
      instruction.entity == entity_name
    end)
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

  defp ensure_no_restrictions!(traits, restrictions, entity_name, scenario) do
    case restrictions.trait_names_by_entity do
      %{^entity_name => requested_trait_names} ->
        case Enum.find(traits, fn
               %SeedFactory.Trait{from: nil} -> false
               %SeedFactory.Trait{from: from} -> from in requested_trait_names
             end) do
          nil ->
            traits

          trait ->
            message =
              case scenario do
                :new ->
                  """
                  Cannot apply trait #{inspect(trait.name)} to entity #{inspect(entity_name)}.
                  The entity was requested with the following traits: #{inspect(requested_trait_names)}
                  """

                :current ->
                  """
                  Cannot apply traits #{inspect(requested_trait_names)} to entity #{inspect(entity_name)}.
                  The entity already exists with traits that depend on requested ones.
                  """
              end

            raise ArgumentError, message
        end

      _ ->
        traits
    end
  end

  defp add_conflicting_commands_to_requirements(requirements, [command_name], required_by) do
    {add_non_conflicting_command_to_requirements(requirements, command_name, required_by, []),
     MapSet.new([command_name])}
  end

  defp add_conflicting_commands_to_requirements(requirements, command_names, required_by) do
    # if the command can be found in requirements, and it doesn't have any conflict, it means, that it was requested
    # without ambiguity, so we can skip conflict resolution for the command
    case Enum.find(
           command_names,
           fn command_name ->
             Map.has_key?(requirements.commands, command_name) and
               not command_or_anything_in_vertical_conflicts?(
                 requirements.commands,
                 command_name
               )
           end
         ) do
      nil ->
        case analyze_conflict_group(requirements, command_names) do
          :new_group ->
            requirements =
              command_names
              |> Enum.reduce(requirements, fn command_name, requirements ->
                add_conflicting_command_to_requirements(
                  requirements,
                  command_name,
                  required_by,
                  command_names
                )
              end)
              |> Map.update!(:unresolved_conflict_groups, &[command_names | &1])

            {requirements, MapSet.new(command_names)}

          :exists ->
            requirements = link_commands(requirements, command_names, required_by)
            {requirements, MapSet.new([])}

          {:is_subset, diff} ->
            requirements =
              diff
              |> Enum.reduce(requirements, &remove_command(&2, &1))
              |> link_commands(command_names, required_by)

            {requirements, MapSet.new([])}

          {:contains_subset, subset} ->
            requirements = link_commands(requirements, subset, required_by)
            {requirements, MapSet.new([])}
        end

      command_name ->
        requirements = link_commands(requirements, command_name, required_by)
        {requirements, MapSet.new()}
    end
  end

  defp analyze_conflict_group(requirements, conflict_group_to_analyze) do
    unresolved_conflict_groups = requirements.unresolved_conflict_groups
    conflict_group_to_analyze_mapset = MapSet.new(conflict_group_to_analyze)

    Enum.find_value(unresolved_conflict_groups, :new_group, fn unresolved_conflict_group ->
      unresolved_conflict_group_mapset = MapSet.new(unresolved_conflict_group)

      cond do
        conflict_group_to_analyze == unresolved_conflict_group ->
          :exists

        MapSet.subset?(conflict_group_to_analyze_mapset, unresolved_conflict_group_mapset) ->
          {:is_subset,
           MapSet.difference(unresolved_conflict_group_mapset, conflict_group_to_analyze_mapset)}

        MapSet.subset?(unresolved_conflict_group_mapset, conflict_group_to_analyze_mapset) ->
          {:contains_subset, unresolved_conflict_group}

        true ->
          false
      end
    end)
  end

  defp command_or_anything_in_vertical_conflicts?(commands, command_name) do
    data = commands[command_name]

    data.conflict_groups != [] or anything_in_vertical_conflicts?(commands, command_name)
  end

  defp anything_in_vertical_conflicts?(commands, command_name) do
    data = commands[command_name]

    Enum.any?(data.required_by, fn
      nil -> false
      command_name -> command_or_anything_in_vertical_conflicts?(commands, command_name)
    end)
  end

  defp add_non_conflicting_command_to_requirements(
         requirements,
         command_name,
         required_by,
         traits
       ) do
    case requirements.commands do
      %{^command_name => data} ->
        requirements
        |> update_in(
          [:commands, command_name],
          &%{
            &1
            | args: squash_args(traits, &1.args),
              required_by: MapSet.put(&1.required_by, required_by)
          }
        )
        |> add_command_name_to_requires_field(required_by, command_name)
        |> auto_resolve_conflict_if_possible(command_name, data.conflict_groups)

      _ ->
        add_new_command_to_requirements(requirements, command_name, %{
          conflict_groups: [],
          traits: traits,
          required_by: required_by
        })
    end
  end

  defp auto_resolve_conflict_if_possible(requirements, command_name, conflict_groups) do
    has_conflict? = conflict_groups != []

    if has_conflict? and
         not anything_in_vertical_conflicts?(requirements.commands, command_name) do
      resolve_conflicts_in_favour_of_the_command(requirements, command_name)
    else
      requirements
    end
  end

  defp add_conflicting_command_to_requirements(
         requirements,
         command_name,
         required_by,
         conflict_group
       ) do
    if Map.has_key?(requirements.commands, command_name) do
      requirements
      |> update_in(
        [:commands, command_name],
        &%{
          &1
          | required_by: MapSet.put(&1.required_by, required_by),
            conflict_groups: [conflict_group | &1.conflict_groups]
        }
      )
      |> add_command_name_to_requires_field(required_by, command_name)
    else
      add_new_command_to_requirements(requirements, command_name, %{
        conflict_groups: [conflict_group],
        traits: [],
        required_by: required_by
      })
    end
  end

  defp add_new_command_to_requirements(requirements, command_name, params) do
    requirements
    |> put_in([:commands, command_name], %{
      conflict_groups: params.conflict_groups,
      requires: MapSet.new(),
      args: squash_args(params.traits),
      required_by: MapSet.new([params.required_by])
    })
    |> add_command_name_to_requires_field(params.required_by, command_name)
  end

  defp link_commands(requirements, command_names, required_by) when is_list(command_names) do
    Enum.reduce(command_names, requirements, &link_commands(&2, &1, required_by))
  end

  defp link_commands(requirements, command_name, required_by) do
    requirements
    |> add_command_name_to_required_by_field(command_name, required_by)
    |> add_command_name_to_requires_field(required_by, command_name)
  end

  defp add_command_name_to_required_by_field(requirements, command_name, command_name_to_add) do
    update_in(
      requirements,
      [:commands, command_name, :required_by],
      &MapSet.put(&1, command_name_to_add)
    )
  end

  defp add_command_name_to_requires_field(requirements, command_name, command_name_to_add) do
    case command_name do
      nil ->
        requirements

      command_name ->
        update_in(
          requirements,
          [:commands, command_name, :requires],
          &MapSet.put(&1, command_name_to_add)
        )
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

  defp fetch_traits!(context, entity_name) do
    case Map.fetch(context.__seed_factory_meta__.traits, entity_name) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "Entity #{inspect(entity_name)} doesn't have traits"
    end
  end

  defp executed_commands_from_traits(traits) do
    traits
    |> Enum.group_by(& &1.exec_step.command_name)
    |> Map.new(fn {command_name, traits} -> {command_name, squash_args(traits)} end)
  end

  defp select_traits_with_dependencies_by_names(trait_names, trait_by_name, entity_name, trail) do
    Enum.flat_map(trait_names, fn trait_name ->
      case Map.fetch(trait_by_name, trait_name) do
        {:ok, trait} ->
          resolve_trait_depedencies(trait, trait_by_name, trail)

        :error ->
          raise ArgumentError,
                "Entity #{inspect(entity_name)} doesn't have trait #{inspect(trait_name)}"
      end
    end)
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

  defp resolve_trait_depedencies(trait, trait_by_name, trail) do
    case trait.from do
      nil ->
        [trait]

      from when is_atom(from) ->
        from_trait = trait_by_name[from]
        [trait | resolve_trait_depedencies(from_trait, trait_by_name, trail)]

      from_any_of when is_list(from_any_of) ->
        from_trait =
          case trail do
            nil ->
              trait_by_name[hd(from_any_of)]

            trail ->
              trait_by_command_name =
                Map.new(from_any_of, fn from ->
                  from_trait = trait_by_name[from]
                  {from_trait.exec_step.command_name, from_trait}
                end)

              Enum.find_value(trail.updated_by, fn command_name ->
                trait_by_command_name[command_name]
              end) || trait_by_command_name[trail.produced_by]
          end

        [trait | resolve_trait_depedencies(from_trait, trait_by_name, trail)]
    end
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
        |> store_trails(command)
        |> sync_current_traits(command, args)

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
      init_requirements()
      |> collect_requirements_for_command(
        context,
        command,
        initial_input,
        nil,
        build_restrictions(context, [])
      )
      |> resolve_conflicts()
      |> exec_requirements(context)
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

  defp resolve_conflicts(%{unresolved_conflict_groups: []} = requirements) do
    requirements
  end

  defp resolve_conflicts(
         %{unresolved_conflict_groups: [[primary_command_name | _] | _]} = requirements
       ) do
    requirements
    |> resolve_conflicts_in_favour_of_the_command(primary_command_name)
    |> resolve_conflicts()
  end

  defp resolve_conflicts_in_favour_of_the_command(requirements, command_name_to_keep) do
    data = Map.fetch!(requirements.commands, command_name_to_keep)

    all_command_names_in_conflict_groups =
      data.conflict_groups
      |> List.flatten()
      |> Enum.uniq()

    Enum.reduce(
      all_command_names_in_conflict_groups,
      requirements,
      fn command_name, requirements ->
        if command_name == command_name_to_keep do
          requirements
        else
          remove_command(requirements, command_name)
        end
      end
    )
  end

  defp remove_command(requirements, command_name) do
    data = Map.fetch!(requirements.commands, command_name)

    commands =
      requirements.commands
      |> Map.delete(command_name)
      |> remove_command_name_from_requires_field(command_name, data.required_by)

    requirements = %{requirements | commands: commands}

    requirements =
      remove_command_name_from_conflict_groups_if_present(
        requirements,
        data.conflict_groups,
        command_name
      )

    Enum.reduce(
      data.requires,
      requirements,
      &remove_command_while_required_by_is_empty(&2, &1, command_name)
    )
  end

  defp remove_command_while_required_by_is_empty(
         requirements,
         command_name,
         deleted_required_by
       ) do
    data = Map.fetch!(requirements.commands, command_name)
    new_required_by = MapSet.delete(data.required_by, deleted_required_by)

    if Enum.empty?(new_required_by) do
      remove_command(requirements, command_name)
    else
      update_in(requirements, [:commands, command_name], &%{&1 | required_by: new_required_by})
    end
  end

  defp remove_command_name_from_conflict_groups_if_present(
         requirements,
         [],
         _command_name_to_remove
       ) do
    requirements
  end

  defp remove_command_name_from_conflict_groups_if_present(
         requirements,
         conflict_groups,
         command_name_to_remove
       ) do
    conflict_groups
    |> Enum.reduce(requirements, fn conflict_group, requirements ->
      command_names_to_update = List.delete(conflict_group, command_name_to_remove)

      new_conflict_group =
        case command_names_to_update do
          [_] -> []
          group -> group
        end

      if new_conflict_group == conflict_group do
        requirements
      else
        unresolved_conflict_groups =
          List.delete(requirements.unresolved_conflict_groups, conflict_group)

        unresolved_conflict_groups =
          if new_conflict_group == [] do
            unresolved_conflict_groups
          else
            [new_conflict_group | unresolved_conflict_groups]
          end

        commands =
          Enum.reduce(command_names_to_update, requirements.commands, fn command_name, commands ->
            Map.update!(
              commands,
              command_name,
              &%{
                &1
                | conflict_groups:
                    replace_conflict_group(&1.conflict_groups, conflict_group, new_conflict_group)
              }
            )
          end)

        %{commands: commands, unresolved_conflict_groups: unresolved_conflict_groups}
      end
    end)
  end

  defp replace_conflict_group(conflict_groups, old, new) do
    [new | List.delete(conflict_groups, old)]
  end

  defp remove_command_name_from_requires_field(
         commands,
         command_name_to_remove,
         target_command_names
       ) do
    Enum.reduce(target_command_names, commands, fn
      nil, commands ->
        commands

      required_by_command_name, commands ->
        if Map.has_key?(commands, required_by_command_name) do
          update_in(
            commands,
            [required_by_command_name, :requires],
            &MapSet.delete(&1, command_name_to_remove)
          )
        else
          commands
        end
    end)
  end

  defp exec_requirements(requirements, context) when requirements.commands == %{} do
    context
  end

  defp exec_requirements(requirements, context) do
    requirements =
      add_additional_requirements_to_commands_that_delete_entities(requirements, context)

    requirements.commands
    |> topologically_sorted_commands()
    |> Enum.reduce(context, fn
      command_name, context ->
        # command should not be executed if it can be found in `required_by` field but not in `requirements` by key .
        # it can't be found if it is nil (top level required_by value) or if it was removed by `pre_exec` function
        case requirements.commands[command_name] do
          nil -> context
          %{args: args} -> exec(context, command_name, args)
        end
    end)
  end

  # such commands should be executed after commands which use entities that will be deleted
  defp add_additional_requirements_to_commands_that_delete_entities(requirements, context) do
    commands = requirements.commands

    Enum.reduce(commands, requirements, fn {command_name, data}, requirements ->
      command = fetch_command_by_name!(context, command_name)

      command_names_to_link =
        Enum.flat_map(command.deleting_instructions, fn %{entity: entity} ->
          Enum.flat_map(data.requires, fn requires_command_name ->
            Enum.filter(
              commands[requires_command_name].required_by,
              fn
                nil ->
                  false

                required_by_command_name ->
                  required_by_command_name != command_name and
                    entity in fetch_command_by_name!(context, required_by_command_name).required_entities
              end
            )
          end)
        end)

      link_commands(requirements, command_names_to_link, command_name)
    end)
  end

  defp topologically_sorted_commands(commands) do
    commands
    |> Enum.reduce(Graph.new(), fn {command_name, %{required_by: required_by}}, graph ->
      Enum.reduce(required_by, graph, fn dependent_command, graph ->
        Graph.add_edge(graph, command_name, dependent_command)
      end)
    end)
    |> Graph.topsort()
  end

  defp sync_current_traits(context, command, args) do
    traits_diff =
      Enum.flat_map(
        command.producing_instructions ++ command.updating_instructions,
        fn %{entity: entity} ->
          case context.__seed_factory_meta__.traits[entity][:by_command_name][command.name] do
            nil ->
              []

            possible_traits ->
              binding_name = binding_name(context, entity)

              diff =
                Enum.reduce(possible_traits, {[], []}, fn trait, {remove, add} = acc ->
                  if args_match?(trait, args) do
                    {List.wrap(trait.from) ++ remove, [trait.name | add]}
                  else
                    acc
                  end
                end)

              [{binding_name, diff}]
          end
        end
      )

    context
    |> update_meta(:current_traits, fn current_traits ->
      Enum.reduce(traits_diff, current_traits, fn {binding_name, {remove, add}}, current_traits ->
        current_trait_names = current_traits[binding_name] || []
        new_trait_names = (current_trait_names -- remove) ++ add
        Map.put(current_traits, binding_name, new_trait_names)
      end)
    end)
    |> delete_from_current_traits(command.deleting_instructions)
  end

  defp store_trails(context, command) do
    context =
      Enum.reduce(command.producing_instructions, context, fn instruction, context ->
        binding_name = binding_name(context, instruction.entity)

        trail = SeedFactory.Trail.new(command.name)
        update_meta(context, :trails, &Map.put(&1, binding_name, trail))
      end)

    context =
      Enum.reduce(command.updating_instructions, context, fn instruction, context ->
        binding_name = binding_name(context, instruction.entity)

        update_meta(context, :trails, fn trails ->
          Map.update!(trails, binding_name, &SeedFactory.Trail.add_updated_by(&1, command.name))
        end)
      end)

    case command.deleting_instructions do
      [] ->
        context

      deleting_instructions ->
        binding_names = Enum.map(deleting_instructions, &binding_name(context, &1.entity))

        update_meta(context, :trails, &Map.drop(&1, binding_names))
    end
  end

  defp current_trait_names(context, binding_name) do
    context.__seed_factory_meta__.current_traits[binding_name] || []
  end

  defp delete_from_current_traits(context, deleting_instructions) do
    case deleting_instructions do
      [] ->
        context

      deleting_instructions ->
        binding_names = Enum.map(deleting_instructions, &binding_name(context, &1.entity))

        update_meta(context, :current_traits, &Map.drop(&1, binding_names))
    end
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
    %{
      trait_names_by_entity: Map.new(entities_with_trait_names),
      traits:
        Enum.flat_map(entities_with_trait_names, fn
          {_entity_name, []} ->
            []

          {entity_name, trait_names} ->
            %{by_name: trait_by_name} = fetch_traits!(context, entity_name)

            select_traits_with_dependencies_by_names(
              trait_names,
              trait_by_name,
              entity_name,
              context.__seed_factory_meta__.trails[entity_name]
            )
        end)
    }
  end

  defp maybe_map(value, map) do
    if map do
      map.(value)
    else
      value
    end
  end

  defp init_requirements do
    %{commands: %{}, unresolved_conflict_groups: []}
  end
end
