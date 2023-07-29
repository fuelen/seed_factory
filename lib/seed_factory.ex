defmodule SeedFactory do
  @moduledoc """
  A utility for producing entities using business logic defined by your application.

  The main idea of `SeedFactory` is to produce entities in tests according to your application business logic (read as context functions if you use https://hexdocs.pm/phoenix/contexts.html)
  whenever it is possible and avoid direct inserts to the database (opposed to `ex_machina`).
  This approach allows to minimize testing of invalid states as you're not forced to keep complex database structure in your head in order to prepare test data.

  **Context**, **entities** and **commands** are the core concepts of the library.

  Context is a map which can be populated by entities using commands.
  The schema with instructions on how commands modify context is described using DSL with the help of `SeedFactory.Schema` module.

  Commands can be used to:
  * produce entity (put new data in the context)
  * update entity (replace the existing entity in the context)
  * delete entity (remove the entity from the context)

  An entity can be produced only by one command.
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
  Also, it describes traits of `:user` entity.

  In order to use the schema, put metadata about it to the context using `init/2` function:
  ```elixir
  context = %{}
  context = init(context, MyApp.SeedFactorySchema)
  ```
  If you use `SeedFactory` in tests, use `SeedFactory.Test` helper module instead.

  Now, `exec/2` function can be used to execute a command:
  ```elixir
  context = exec(context, :create_company)
  ```
  The code above will generate arguments for `:create_company` command, execute a resolver with generated arguments and put company to context using `:company` key.
  `exec/3` can be used if you want to specify parameters explicitly:
  ```elixir
  context = exec(context, :create_company, name: "GitHub")
  ```

  Because exec function returns `t:context/0`, it is convenient to chain `exec` calls with pipe operator:
  ```elixir
  context =
    context
    |> exec(:create_company)
    |> exec(:create_user, name: "John Doe")
  ```
  In order to get a value for the `:command` parameter of the `:create_user` command, the corresponding entity was taken from the context.
  However, it is not necessary to do so, as `SeedFactory` can automatically execute commands which produce dependent entities.
  The code above has the same effect as a single call to `:create_user` command:
  ```elixir
  context = exect(context, :create_user, name: "John Doe")
  ```

  If you're not interested in explicit providing parameters to commands, then you can use `produce/2` function to produce
  requested entities with automatic execution of all dependend commands:
  ```elixir
  context = produce(context, :user)
  ```
  Even though `:user` is the only entity specified explicitly, `context` will have 3 new keys: `:company`, `:user` and `:profile`.

  > #### Tip {: .tip}
  > It is recommended to specify all entities explicitly in which you're insterested:
  > ```elixir
  > # good
  > %{user: user} = produce(contex, :user)
  >
  > # good
  > %{user: user, profile: profile} = produce(contex, [:user, :profile])
  >
  > # good
  > %{user: user, profile: profile, company: company} = produce(contex, [:user, :profile, :company])
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
    |> rebind([user: :user2, profile: :profile1], &exec(&1, :create_user))
  ```
  The snippet above puts the following keys to the context: `:company`, `:user1`, `:profile1`, `:user2`, `:profile2`.
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

  To achive the same result, traits can be passed to `produce/2`:
  ```elixir
  produce(context, user: [:admin, :active])
  ```

  If you want to specify traits and assign an entity to the context with the different name, then use `:as` option:
  ```elixir
  %{admin: admin} = produce(context, user: [:admin, as: :admin])
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
      %{...}
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
  Produces entities by executing corresponding commands.

  ## Examples

      %{user: _} = produce(context, :user)

      %{user: _, company: _} = produce(context, [:user, :company])

      %{user1: _} = produce(context, user: :user1)

      %{user: _} = produce(context, user: [:active, :admin])

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

    rebind(context, rebinding, fn context ->
      context
      |> requirements_of_entities_with_trait_names(
        entities_with_trait_names,
        nil,
        %{},
        Map.new(entities_with_trait_names)
      )
      |> exec_requirements(context)
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
      %{user: user1} = pre_produce(context, :user)
      %{user: user2} = pre_produce(context, :user)
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

    rebind(context, rebinding, fn context ->
      context
      |> requirements_of_entities_with_trait_names(
        entities_with_trait_names,
        nil,
        %{},
        Map.new(entities_with_trait_names)
      )
      |> Map.reject(fn {_key, %{required_by: required_by}} -> nil in required_by end)
      |> exec_requirements(context)
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

  defp command_requirements(
         context,
         command,
         initial_input,
         required_by,
         requirements,
         restrictions
       ) do
    entities_with_trait_names = parameter_requirements(command, initial_input)

    requirements_of_entities_with_trait_names(
      context,
      entities_with_trait_names,
      required_by,
      requirements,
      restrictions
    )
  end

  defp requirements_of_entities_with_trait_names(
         _context,
         entities_with_trait_names,
         _required_by,
         requirements,
         _limitations
       )
       when map_size(entities_with_trait_names) == 0 do
    requirements
  end

  defp requirements_of_entities_with_trait_names(
         context,
         entities_with_trait_names,
         required_by,
         initial_requirements,
         restrictions
       ) do
    {requirements, command_names} =
      Enum.reduce(
        entities_with_trait_names,
        {initial_requirements, MapSet.new()},
        fn {entity_name, trait_names}, {requirements, command_names} = acc ->
          # duplicated values are produced by parameter_requirements function after recursive calls to
          # `command_requirements` function
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

                currently_executed =
                  current_trait_names
                  |> select_traits_with_dependencies_by_names(trait_by_name, entity_name)
                  |> ensure_no_restrictions!(restrictions, entity_name, :current)
                  |> executed_commands_from_traits()

                absent_trait_names
                |> select_traits_with_dependencies_by_names(trait_by_name, entity_name)
                |> Enum.group_by(& &1.exec_step.command_name)
                |> Enum.reduce(acc, fn {command_name, traits},
                                       {requirements, command_names} = acc ->
                  case currently_executed[command_name] do
                    nil ->
                      {add_command_to_requirements(
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
              command_name = fetch_command_name_by_entity_name!(context, entity_name)

              {add_command_to_requirements(requirements, command_name, required_by, []),
               MapSet.put(command_names, command_name)}
            else
              %{by_name: trait_by_name} = fetch_traits!(context, entity_name)

              trait_names
              |> select_traits_with_dependencies_by_names(trait_by_name, entity_name)
              |> ensure_no_restrictions!(restrictions, entity_name, :new)
              |> Enum.reduce(acc, fn trait, {requirements, command_names} ->
                command_name = trait.exec_step.command_name

                {
                  add_command_to_requirements(requirements, command_name, required_by, [trait]),
                  MapSet.put(command_names, command_name)
                }
              end)
            end
          end
        end
      )

    Enum.reduce(command_names, requirements, fn command_name, requirements ->
      command = Map.fetch!(context.__seed_factory_meta__.commands, command_name)

      if Map.has_key?(initial_requirements, command_name) or
           anything_was_produced_by_command?(context, command) do
        requirements
      else
        command_requirements(context, command, %{}, command.name, requirements, restrictions)
      end
    end)
  end

  defp fetch_command_by_name!(context, command_name) do
    case Map.fetch(context.__seed_factory_meta__.commands, command_name) do
      {:ok, command} -> command
      :error -> raise ArgumentError, "Unknown command #{inspect(command_name)}"
    end
  end

  defp fetch_command_name_by_entity_name!(context, entity_name) do
    case Map.fetch(context.__seed_factory_meta__.entities, entity_name) do
      {:ok, command_name} -> command_name
      :error -> raise ArgumentError, "Unknown entity #{inspect(entity_name)}"
    end
  end

  defp ensure_no_restrictions!(traits, restrictions, entity_name, scenario) do
    case restrictions do
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

  defp add_command_to_requirements(requirements, command_name, required_by, traits) do
    case requirements do
      %{^command_name => data} ->
        Map.put(requirements, command_name, %{
          args: squash_args(traits, data.args),
          required_by: MapSet.put(data.required_by, required_by)
        })

      _ ->
        Map.put(requirements, command_name, %{
          args: squash_args(traits),
          required_by: MapSet.new([required_by])
        })
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

  defp select_traits_with_dependencies_by_names(trait_names, trait_by_name, entity_name) do
    Enum.flat_map(trait_names, fn trait_name ->
      case Map.fetch(trait_by_name, trait_name) do
        {:ok, trait} ->
          trait |> resolve_trait_depedencies(trait_by_name)

        :error ->
          raise ArgumentError,
                "Entity #{inspect(entity_name)} doesn't have trait #{inspect(trait_name)}"
      end
    end)
  end

  defp squash_args(traits) do
    squash_args(traits, %{})
  end

  defp squash_args(traits, initial_args) do
    Enum.reduce(traits, initial_args, fn trait, acc ->
      case trait.exec_step do
        %{args_pattern: pattern} when is_map(pattern) ->
          deep_merge_maps!(acc, pattern, [])

        %{generate_args: generate_args} when is_function(generate_args) ->
          deep_merge_maps!(acc, generate_args.(), [])

        _ ->
          acc
      end
    end)
  end

  defp deep_merge_maps!(map1, map2, path) do
    Map.merge(map1, map2, fn
      key, v1, v2 when is_map(v1) and is_map(v2) ->
        deep_merge_maps!(v1, v2, path ++ [key])

      _key, v, v ->
        v

      key, v1, v2 ->
        raise ArgumentError, """
        Cannot merge arguments generated by traits.
          Path: #{inspect(path ++ [key])}
          Value 1: #{inspect(v1)}
          Value 2: #{inspect(v2)}
        """
    end)
  end

  defp resolve_trait_depedencies(%{from: nil} = trait, _trait_by_name), do: [trait]

  defp resolve_trait_depedencies(trait, trait_by_name) do
    [trait | resolve_trait_depedencies(trait_by_name[trait.from], trait_by_name)]
  end

  @doc """
  Executes a command and puts its result to the `context`.

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
        |> exec_producing_instructions(command.producing_instructions, resolver_output)
        |> exec_updating_instructions(command.updating_instructions, resolver_output)
        |> exec_deleting_instructions(command.deleting_instructions)
        |> sync_current_traits(command, args)

      {:error, error} ->
        raise "Unable to execue #{inspect(command_name)} command: #{inspect(error)}"
    end
  end

  @doc """
  Creates dependencies needed to execute the command.

  This is useful, when you're interested in side effects and you want to execute the command multiple times with the same input entities.

  ## Example

      # Function :create_user produces multiple entities (:user and :profile), so if you want to
      # produce multiple users using a sequence of `exec` calls, you have to write this:
      %{user1: user1, user2: user2} =
        context
        |> rebind([user: :user1, profile: :profile1], &exec(:create_user, role: :admin))
        |> rebind([user: :user2, profile: :profile2], &exec(:create_user, role: :admin))

      # The code above is a bit wordy in a case when all we need are :user entitities. We have to write
      # rebinding for :profile even though we are't interested in it.

      # A less wordy alternative is:
      context = produce(context, list_of_all_dependencies_with_their_traits)
      %{user: user1} = exec(context, :create_user)
      %{user: user2} = exec(context, :create_user)

      # However, you have to explicitly enumerate all the dependencies.
      # It can be more compact with `pre_exec` function:
      context = pre_exec(context, :create_user)
      %{user: user1} = exec(context, :create_user)
      %{user: user2} = exec(context, :create_user)
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
      context
      |> command_requirements(command, initial_input, nil, %{}, %{})
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

  defp exec_requirements(requirements, context) do
    requirements
    |> topologically_sorted_commands()
    |> Enum.reduce(context, fn
      command_name, context ->
        # command should not be executed if it can be found in `required_by` field but not in `requirements` by key .
        # it can't be found if it is nil (top level required_by value) or if it was removed by `pre_exec` function
        case requirements[command_name] do
          nil -> context
          %{args: args} -> exec(context, command_name, args)
        end
    end)
  end

  defp topologically_sorted_commands(requirements) do
    requirements
    |> Enum.reduce(Graph.new(), fn {command_name, %{required_by: required_by}}, graph ->
      Enum.reduce(required_by, graph, fn dependent_command, graph ->
        Graph.add_edge(graph, command_name, dependent_command)
      end)
    end)
    |> Graph.topsort()
  end

  defp sync_current_traits(context, command, args) do
    (command.producing_instructions ++ command.updating_instructions)
    |> Enum.reduce(
      context,
      fn %{entity: entity}, context ->
        case context.__seed_factory_meta__.traits[entity][:by_command_name][command.name] do
          nil ->
            context

          possible_traits ->
            binding_name = binding_name(context, entity)
            current_trait_names = current_trait_names(context, binding_name)

            {remove, add} =
              possible_traits
              |> Enum.reduce({[], []}, fn trait, {remove, add} = acc ->
                args_match? = args_match?(trait, args)

                cond do
                  args_match? and is_nil(trait.from) ->
                    {remove, [trait.name | add]}

                  args_match? and trait.from in current_trait_names ->
                    {[trait.from | remove], [trait.name | add]}

                  true ->
                    acc
                end
              end)

            new_trait_names = (current_trait_names -- remove) ++ add

            update_meta(context, :current_traits, &Map.put(&1, binding_name, new_trait_names))
        end
      end
    )
    |> delete_from_current_traits(command.deleting_instructions)
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
      {key, value} when is_map(value) -> deep_equal_maps?(value, map2[key])
      {key, value} -> map2[key] == value
    end)
  end

  defp exec_producing_instructions(context, instructions, resolver_output) do
    Enum.reduce(instructions, context, fn %SeedFactory.ProducingInstruction{
                                            entity: entity_name,
                                            from: from
                                          },
                                          context ->
      binding_name = binding_name(context, entity_name)

      if Map.has_key?(context, binding_name) do
        message =
          "Cannot put entity #{inspect(entity_name)} to the context: key #{inspect(binding_name)} already exists"

        raise ArgumentError, message
      else
        Map.put(context, binding_name, Map.fetch!(resolver_output, from))
      end
    end)
  end

  defp exec_updating_instructions(context, instructions, resolver_output) do
    Enum.reduce(instructions, context, fn %SeedFactory.UpdatingInstruction{
                                            entity: entity_name,
                                            from: from
                                          },
                                          context ->
      binding_name = binding_name(context, entity_name)

      if Map.has_key?(context, binding_name) do
        Map.put(context, binding_name, Map.fetch!(resolver_output, from))
      else
        message =
          "Cannot update entity #{inspect(entity_name)}: key #{inspect(binding_name)} doesn't exist in the context"

        raise ArgumentError, message
      end
    end)
  end

  defp exec_deleting_instructions(context, instructions) do
    Enum.reduce(instructions, context, fn %SeedFactory.DeletingInstruction{entity: entity_name},
                                          context ->
      binding_name = binding_name(context, entity_name)

      if Map.has_key?(context, binding_name) do
        Map.delete(context, binding_name)
      else
        message =
          "Cannot delete entity #{inspect(entity_name)} from the context: key #{inspect(binding_name)} doesn't exist"

        raise message
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

  defp maybe_map(value, map) do
    if map do
      map.(value)
    else
      value
    end
  end
end
