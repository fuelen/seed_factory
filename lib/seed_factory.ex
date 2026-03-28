defmodule SeedFactory do
  @moduledoc """
  A toolkit for test data generation.

  The main idea of `SeedFactory` is to generate data in tests according to your application business logic (read as
  context functions if you use [Phoenix Contexts](https://hexdocs.pm/phoenix/contexts.html)) whenever possible
  and avoid direct inserts to the database (as opposed to `ex_machina`).
  This approach allows you to minimize testing of invalid states as you're not forced to keep complex database structure in your head in order to prepare test data.
  The library is completely agnostic to the database toolkit.

  ## Core concepts

  **Context** is a `t:map/0` which can be populated with entities using commands.

  The schema with instructions on how commands modify context is described using DSL with the help of `SeedFactory.Schema` module.

  **Commands** can be used to:
  * produce entity (put new data in the context)
  * update entity (replace the existing entity in the context)
  * delete entity (remove the entity from the context)

  A command has params with instructions on how to generate arguments for a resolver if they are not passed explicitly with `exec/3` function.
  The instruction can be specified using one of these options:
  * `:value` - any term. This option is used by default with the value of `nil`.
  * `:generate` - a zero-arity function for generating data.
  * `:entity` - an atom which points to an entity which should be taken from the context. If a required entity cannot
  be found in a context, then `SeedFactory` automatically executes a corresponding command which produces the entity.
  The `:entity` option also supports `:with_traits` to require that the entity has specific traits before it can be used as a dependency.

  **Traits** are labels assigned to entities when specific commands with specific arguments are executed.
  They describe how an entity was created or what state it is in. Traits can build on each other using `from` —
  for example, an `:active` trait can require `:pending` first, meaning the entity must go through the `:pending`
  state before becoming `:active`. Traits can also be tied to specific argument values using `args_pattern`.

  ## Schema example

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
      # with_traits ensures the user has the :pending trait before activation
      param :user, entity: :user, with_traits: [:pending]

      resolve(fn args ->
        user = MyApp.Users.activate_user!(args.user)

        {:ok, %{user: user}}
      end)

      update :user
    end

    # :pending is assigned when :create_user is executed
    trait :pending, :user do
      exec :create_user
    end

    # :active requires :pending first — :activate_user replaces :pending with :active
    trait :active, :user do
      from :pending
      exec :activate_user
    end

    # :admin and :normal are determined by the :role argument
    trait :admin, :user do
      exec :create_user, args_pattern: %{role: :admin}
    end

    trait :normal, :user do
      exec :create_user, args_pattern: %{role: :normal}
    end
  end
  ```

  ## Getting started

  To start using the schema, put metadata about it to the context using `init/2` function:
  ```elixir
  context = %{}
  context = init(context, MyApp.SeedFactorySchema)
  ```
  If you use `SeedFactory` in tests with `ExUnit`, check out `SeedFactory.Test`. This module adds initialization using `ExUnit.Callbacks.setup_all/2` callback
  and imports functions.

  ## exec

  `exec/2` function can be used to execute a command:
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

  ## produce

  If you're not interested in explicitly providing parameters to commands, you can use `produce/2` to produce
  requested entities with automatic execution of all dependent commands:
  ```elixir
  context = produce(context, :user)
  ```
  Even though `:user` is the only entity specified explicitly, `context` will have 3 new keys: `:company`, `:user` and `:profile`.

  Traits can be specified to control how entities are created. SeedFactory figures out
  the command chain from the trait definitions:
  ```elixir
  # these two are equivalent
  context = produce(context, user: [:admin, :active])

  context =
    context
    |> exec(:create_user, role: :admin)
    |> exec(:activate_user)
  ```

  Use the `:as` option to combine traits with rebinding:
  ```elixir
  %{active_admin: active_admin} = produce(context, user: [:admin, :active, as: :active_admin])
  ```

  > #### Tip {: .tip}
  > Pattern match on what you pass to `produce/2`. This makes the test self-documenting
  > and avoids relying on implicitly created entities:
  > ```elixir
  > # good — matches what was requested
  > %{user: user} = produce(context, :user)
  >
  > # good — multiple entities requested and matched
  > %{user: user, profile: profile} = produce(context, [:user, :profile])
  >
  > # bad — matching entities that were not explicitly requested
  > %{user: user, profile: profile, company: company} = produce(context, :user)
  > ```

  ## Rebinding

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

  ## Debugging

  `SeedFactory` tracks how each entity was created and modified.
  You can inspect `__seed_factory_meta__` key in the context to review currently assigned traits and execution history:

  ```elixir
  context |> produce(user: [:admin, :active]) |> IO.inspect()
  # %{
  #   __seed_factory_meta__: #SeedFactory.Meta<
  #     current_traits: %{company: [], profile: [], user: [:admin, :active]},
  #     trails: %{
  #       company: #trail[:create_company],
  #       profile: #trail[:create_user],
  #       user: #trail[create_user: +[:pending, :admin] -> activate_user: +[:active] -[:pending]]
  #     },
  #     execution_history: [
  #       #execution[produce(user: [:admin, :active]): create_company → create_user → activate_user]
  #     ],
  #     ...
  #   >,
  #   company: %Company{...},
  #   profile: %Profile{...},
  #   user: %User{...}
  # }
  ```

  If an exception or error occurs during command execution, `SeedFactory` raises `SeedFactory.ExecError`
  with structured metadata including the execution plan, trails, and current traits at the time of failure:

  ```
  ** (SeedFactory.ExecError) unable to execute :create_user command: :email_already_taken

  Execution plan:
    ✔ :create_company
    ✖ :create_user

  Current traits:
    %{company: []}
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
  Creates a scoped context where entities are assigned under different names.

  Within the callback, all commands that produce, update, delete, or depend on
  the specified entities will use the remapped names. The rebinding is scoped to
  the callback — it does not affect the context outside of it.

  This is useful when you need to produce the same entity multiple times and
  control how they relate to each other. For simpler cases where you don't need
  to control relationships, `produce/2` with rebinding is enough:

      context |> produce(company: :company1) |> produce(company: :company2)

  ## Example

      # :product requires :company. Here we create 2 companies and 1 product.
      # Inside the first rebind, :company refers to :company1 and :product to :product1,
      # so the product is linked to company1.
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
  Produces entities with their dependencies resolved automatically.

  Analyzes the schema to determine which commands need to be executed and in what order.
  Entities that already exist in the context are reused. The order of specified entities
  doesn't matter.

  ## Examples

      # produce a single entity (dependencies like :company are created automatically)
      %{user: _} = produce(context, :user)

      # produce multiple entities
      %{user: _, company: _} = produce(context, [:user, :company])

      # rebind entity to a different name
      %{user1: _} = produce(context, user: :user1)

      # specify traits
      %{user: _} = produce(context, user: [:active, :admin])

      # apply traits incrementally — first create a pending admin, then activate
      %{user: _} = context |> produce(user: [:pending, :admin]) |> produce(user: [:active])

      # combine traits with rebinding using :as option
      %{user1: _} = produce(context, user: [:active, :admin, as: :user1])

  ## Multiple commands producing the same entity

  If the same entity can be produced by multiple commands, the first declared command
  is used by default. Traits allow you to pick a specific command. For example, given:

      command :create_draft_project do
        # ...
        produce :draft_project
      end

      command :import_draft_project do
        # ...
        produce :draft_project
      end

      trait :created, :draft_project do
        exec :create_draft_project
      end

      trait :imported, :draft_project do
        exec :import_draft_project
      end

  Then:

      # uses :create_draft_project (first declared) and assigns the :created trait
      produce(context, :draft_project)

      # equivalent to the above, but explicit
      produce(context, draft_project: [:created])

      # uses :import_draft_project
      produce(context, draft_project: [:imported])
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

    Context.track_execution(
      context,
      {:produce, entities_with_trait_names},
      fn context ->
        Context.rebind(context, rebinding, fn context ->
          Context.lock_creation_of_dependent_entities(context, fn context ->
            context
            |> Requirements.new(entities_with_trait_names)
            |> Requirements.for_entities_with_trait_names(entities_with_trait_names, nil)
            |> Requirements.unwrap!()
            |> Requirements.resolve_conflicts()
            |> Requirements.apply_to_context(&exec/3)
          end)
        end)
      end
    )
  end

  def produce(context, entity)
      when is_map_key(context, :__seed_factory_meta__) and is_atom(entity) do
    produce(context, [entity])
  end

  @doc """
  Produces all dependencies needed for specified entities, without producing the entities themselves.

  Works like `pre_exec/3`, but operates on entities instead of commands. The dependency tree
  is derived from the commands that would produce the requested entities.

  When traits are specified, the full command chain is analyzed — including update commands.
  All their dependencies are created, but the requested entity itself is not.
  For example, if `:activate_user` updates `:user` and depends on `:team`,
  then `pre_produce(context, user: [:active])` will create `:team` (and all other
  dependencies in the chain) without creating the `:user`.

  ## Examples

      # Create all dependencies for :article (e.g. :blog, :category, :author)
      # without creating the article itself
      context = pre_produce(context, :article)

      %{article: article1} = produce(context, :article)
      %{article: article2} = produce(context, :article)

  Accepts a list with traits, same as `produce/2`:

      context = pre_produce(context, [:article, user: [:active, :admin]])
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

    Context.track_execution(
      context,
      {:pre_produce, entities_with_trait_names},
      fn context ->
        Context.rebind(context, rebinding, fn context ->
          Context.lock_creation_of_dependent_entities(context, fn context ->
            context
            |> Requirements.new(entities_with_trait_names)
            |> Requirements.for_entities_with_trait_names(entities_with_trait_names, nil)
            |> Requirements.unwrap!()
            |> Requirements.resolve_conflicts()
            |> Requirements.delete_explicitly_requested_commands()
            |> Requirements.apply_to_context(&exec/3)
          end)
        end)
      end
    )
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

    Context.track_execution(
      context,
      {:exec, command_name},
      &exec_command(&1, command, initial_input)
    )
  end

  defp exec_command(context, command, initial_input) do
    context = create_dependent_entities_if_needed(context, command, initial_input)

    args =
      SeedFactory.Params.prepare_args(
        command.params,
        initial_input,
        &Context.fetch_entity!(context, &1)
      )

    resolver_output = resolve!(command, args, context.__seed_factory_meta__)

    context
    |> Context.exec_producing_instructions(command, resolver_output)
    |> Context.exec_updating_instructions(command, resolver_output)
    |> Context.exec_deleting_instructions(command)
    |> Context.store_trails_and_sync_current_traits(command, args)
    |> Context.record_command(command.name)
  end

  @doc """
  Creates all dependent entities needed for a command, without executing the command itself.

  This is useful when you want to execute the same command multiple times with shared dependencies.
  It is especially handy when a command has many dependencies — `pre_exec` resolves all of them
  automatically, so you don't have to enumerate them yourself.

  ## Example

  Consider a schema where `:publish_article` depends on `:blog`, `:category`,
  and `:author` (with trait `:active`):

      command :publish_article do
        param :blog, entity: :blog
        param :category, entity: :category
        param :author, entity: :author, with_traits: [:active]
        param :title, generate: &Faker.Lorem.sentence/0
        # ...
        produce :article
      end

  Without `pre_exec`, you would have to manually set up all the dependencies:

      context = produce(context, [:blog, :category, author: [:active]])

      %{article: article1} = exec(context, :publish_article, title: "First")
      %{article: article2} = exec(context, :publish_article, title: "Second")

  With `pre_exec`, the same is achieved without knowing the dependency tree:

      context = pre_exec(context, :publish_article)

      %{article: article1} = exec(context, :publish_article, title: "First")
      %{article: article2} = exec(context, :publish_article, title: "Second")
  """
  @spec pre_exec(context(), command_name :: atom(), initial_input :: map() | keyword()) ::
          context()
  def pre_exec(context, command_name, initial_input \\ %{})
      when is_map_key(context, :__seed_factory_meta__) and is_atom(command_name) and
             (is_map(initial_input) or is_list(initial_input)) do
    command = Context.fetch_command!(context, command_name)

    initial_input = Map.new(initial_input)

    Context.track_execution(context, {:pre_exec, command_name}, fn context ->
      create_dependent_entities_if_needed(context, command, initial_input)
    end)
  end

  defp resolve!(command, args, meta) do
    try do
      command.resolve.(args)
    rescue
      e ->
        reraise build_exec_error(meta, command.name, exception: e, stacktrace: __STACKTRACE__),
                __STACKTRACE__
    end
    |> case do
      {:ok, resolver_output} when is_map(resolver_output) ->
        resolver_output

      {:error, error} ->
        raise build_exec_error(meta, command.name, error: error)
    end
  end

  defp build_exec_error(meta, command_name, extra) do
    plan =
      case meta.current_execution do
        %{commands: [_ | _] = commands} ->
          commands
          |> Enum.map(&{&1, :completed})
          |> Enum.reverse([{command_name, :failed}])

        _ ->
          nil
      end

    SeedFactory.ExecError.exception(
      Keyword.merge(
        [
          command: command_name,
          execution_plan: plan,
          trails: meta.trails,
          current_traits: meta.current_traits
        ],
        extra
      )
    )
  end

  defp create_dependent_entities_if_needed(context, command, initial_input) do
    Context.lock_creation_of_dependent_entities(context, fn context ->
      context
      |> Requirements.new([])
      |> Requirements.for_command(command, initial_input, nil)
      |> Requirements.unwrap!()
      |> Requirements.resolve_conflicts()
      |> Requirements.apply_to_context(&exec/3)
    end)
  end
end
