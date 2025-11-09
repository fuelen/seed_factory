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
  alias SeedFactory.Context
  alias SeedFactory.Requirements

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
  defdelegate init(context, schema), to: Context

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
  defdelegate rebind(context, rebinding, callback), to: Context

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
  def produce(context, entities_and_rebinding)
      when is_map_key(context, :__seed_factory_meta__) and is_list(entities_and_rebinding) do
    {entities_with_trait_names, rebinding} = split_entities_and_rebinding(entities_and_rebinding)

    Context.rebind(context, rebinding, fn context ->
      Context.lock_creation_of_dependent_entities(context, fn context ->
        context
        |> Requirements.new(entities_with_trait_names)
        |> Requirements.for_entities_with_trait_names(entities_with_trait_names, nil)
        |> Requirements.resolve_conflicts()
        |> Requirements.apply_to_context(&exec/3)
      end)
    end)
  end

  def produce(context, entity)
      when is_map_key(context, :__seed_factory_meta__) and is_atom(entity) do
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
  def pre_produce(context, entities_and_rebinding)
      when is_map_key(context, :__seed_factory_meta__) and is_list(entities_and_rebinding) do
    {entities_with_trait_names, rebinding} = split_entities_and_rebinding(entities_and_rebinding)

    Context.rebind(context, rebinding, fn context ->
      Context.lock_creation_of_dependent_entities(context, fn context ->
        context
        |> Requirements.new(entities_with_trait_names)
        |> Requirements.for_entities_with_trait_names(entities_with_trait_names, nil)
        |> Requirements.resolve_conflicts()
        |> Requirements.delete_explicitly_requested_commands()
        |> Requirements.apply_to_context(&exec/3)
      end)
    end)
  end

  def pre_produce(context, entity)
      when is_map_key(context, :__seed_factory_meta__) and is_atom(entity) do
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
  def exec(context, command_name, initial_input \\ %{})
      when is_map_key(context, :__seed_factory_meta__) and is_atom(command_name) and
             (is_map(initial_input) or is_list(initial_input)) do
    command = Context.fetch_command!(context, command_name)

    initial_input = Map.new(initial_input)
    context = create_dependent_entities_if_needed(context, command, initial_input)

    args =
      SeedFactory.Params.prepare_args(
        command.params,
        initial_input,
        &Context.fetch_entity!(context, &1)
      )

    case command.resolve.(args) do
      {:ok, resolver_output} when is_map(resolver_output) ->
        context
        |> Context.exec_producing_instructions(command, resolver_output)
        |> Context.exec_updating_instructions(command, resolver_output)
        |> Context.exec_deleting_instructions(command)
        |> Context.store_trails_and_sync_current_traits(command, args)

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
  def pre_exec(context, command_name, initial_input \\ %{})
      when is_map_key(context, :__seed_factory_meta__) and is_atom(command_name) and
             (is_map(initial_input) or is_list(initial_input)) do
    command = Context.fetch_command!(context, command_name)

    initial_input = Map.new(initial_input)
    create_dependent_entities_if_needed(context, command, initial_input)
  end

  defp create_dependent_entities_if_needed(context, command, initial_input) do
    Context.lock_creation_of_dependent_entities(context, fn context ->
      context
      |> Requirements.new([])
      |> Requirements.for_command(command, initial_input, nil)
      |> Requirements.resolve_conflicts()
      |> Requirements.apply_to_context(&exec/3)
    end)
  end
end
