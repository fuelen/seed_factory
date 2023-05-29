defmodule SeedFactory do
  @moduledoc """
  A utility for producing entities using business logic defined by your application.

  The main idea of `SeedFactory` is to produce entities in tests according to your application business logic (read as context functions if you use https://hexdocs.pm/phoenix/contexts.html)
  whenever it is possible and avoid direct inserts to the database (opposed to `ex_machina`).
  This approach allows to minimize testing of invalid states as you're not forced to keep complex database structure in your head in order to prepare test data.

  **Context**, **Entities** and **commands** are the core concepts of the library.

  Context is a map which can be populated by entities using commands.
  The schema with instructions on how commands modify context is described using DSL with the help of `SeedFactory.Schema` module.

  Commands can be used to:
  * produce entity (put new data in the context)
  * update entity (replace the existing entity in the context)
  * delete entity (remove the entity from the context)

  An entity can be produced only by one command.
  When a command is executed, produced entities are assigned to the context using the name of the entity as a key.
  A command has params with instructions on how to generate arguments for a resolver if they are not passed explicitly with `exec/3` function.
  The instruction can be either a zero-arity function or an atom. A zero-arity function is used for generating data.
  An atom is used to specify an entity which should be taken from the context. If a required entity cannot
  be found in a context, then `SeedFactory` automatically executes a corresponding command which produces the entity.

  Let's take a look at an example of a simple schema.
  ```elixir
  defmodule MyApp.SeedFactorySchema do
    use SeedFactory.Schema

    command :create_company do
      param :name, &Faker.Company.name/0

      resolve(fn args ->
        with {:ok, company} <- MyApp.Companies.create_company(args) do
          {:ok, %{company: company}}
        end
      end)

      produce :company, from: :company
    end

    command :create_user do
      param :name, &Faker.Person.name/0
      param :company, :company

      resolve(fn args -> MyApp.Users.create_user(args.company, args.name) end)

      produce :user, from: :user
      produce :profile, from: :profile
    end
  end
  ```
  The schema above describes how to produce 3 entities (`:company`, `:user` and `:profile`) using 2 commands (`:create_user` and `:create_company`).

  In order to use the schema, we need to put metadata about it to the context using `init/2` function:
  ```elixir
  context = %{}
  context = init(context, MyApp.SeedFactorySchema)
  ```
  If you use `SeedFactory` in tests, use `SeedFactory.Test` helper module instead.

  Now, we can use `produce/2` to produce entities using commands defined in the schema:

  ```elixir
  context = produce(context, :user)
  ```

  After executing the code above, `context` will have 3 new keys: `:company`, `:user` and `:profile`.
  `SeedFactory` automatically executes a chain of commands needed to produce `:user` entity. In this case `:company`
  was produced by the `:create_company` command before resolving the `:create_user` command.

  `exec/3` can be used if you want to specify parameters explicitly:

  ```elixir
  context =
    context
    |> exec(:create_company, name: "GitHub")
    |> exec(:create_user, name: "John Doe")
  ```

  `exec/3` fails if produced entities are already present in the context.
  It is possible to rebind entities in order to assign them to the context with the different name:

  ```elixir
  context =
    context
    |> produce(user: :user1, profile: :profile1)
    |> produce(user: :user2, profile: :profile2)
  ```

  The snippet above puts the following keys to the context: `:company`, `:user1`, `:profile1`, `:user2`, `:profile2`.
  The `:company` is shared in this case, so two users have different profiles and belong to the same company.

  Let's create 2 companies with 1 user in each and pass names to companies explicitly:

  ```elixir
  context =
    context
    |> rebind([company: :company1, user: :user1, profile: :profile1], fn context ->
      context
      |> exec(:create_company, name: "GitHub")
      |> produce(:user)
    end)
    |> rebind([company: :company2, user: :user2, profile: :profile2], fn context ->
      context
      |> exec(:create_company, name: "Microsoft")
      |> produce(:user)
    end)
  ```
  """
  @type context :: map()
  @type entity_name :: atom()
  @type rebinding_rule :: {entity_name(), rebind_as :: atom()}

  @doc """
  Puts metadata about `schema` to `context`, so `context` becomes usable by `rebind/3`, `produce/2` and `exec/3`.

  ## Example

      iex> context = %{}
      ...> init(context, MySeedFactorySchema)
      %{...}
  """
  @spec init(context(), schema :: module) :: context()
  def init(context, schema) do
    Map.put(
      context,
      :__seed_factory_meta__,
      SeedFactory.Meta.new(schema)
    )
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
        if context.__seed_factory_meta__.entities_rebinding do
          raise "Nested rebinding is not supported"
        end

        rebinding = Map.new(rebinding)

        context
        |> Map.update!(:__seed_factory_meta__, fn meta ->
          %{meta | entities_rebinding: rebinding}
        end)
        |> callback.()
        |> Map.update!(:__seed_factory_meta__, fn meta -> %{meta | entities_rebinding: nil} end)
    end
  end

  @doc """
  Produces entities by executing corresponding commands.

  ## Examples

      %{user: _} = produce(context, :user)

      %{user: _, company: _} = produce(context, [:user, :company])

      %{user1: _,} = produce(context, user: :user1)
  """
  @spec produce(context(), entity_name() | [entity_name() | rebinding_rule()]) :: context()
  def produce(context, entities) when is_list(entities) do
    command_name_by_entity_name = context.__seed_factory_meta__.entities

    {entities, rebinding} =
      Enum.map_reduce(entities, [], fn
        {entity_name, _} = rebinding, acc -> {entity_name, [rebinding | acc]}
        entity_name, acc -> {entity_name, acc}
      end)

    rebind(context, rebinding, fn context ->
      Enum.reduce(entities, context, fn
        entity_name, context ->
          binding_name = binding_name(context, entity_name)

          if Map.has_key?(context, binding_name) do
            context
          else
            exec(context, Map.fetch!(command_name_by_entity_name, entity_name), [])
          end
      end)
    end)
  end

  def produce(context, entity) when is_atom(entity) do
    produce(context, [entity])
  end

  @doc """
  Executes a command and puts its result to `context`.

  ## Example

      iex> context = %{}
      ...> context = init(context, MySeedFactorySchema)
      ...> context = exec(context, :create_user, first_name: "John", last_name: "Doe")
      ...> Map.take(context.user, [:first_name, :last_name])
      %{first_name: "John", last_name: "Doe"}
  """
  @spec exec(context(), command_name :: atom(), initial_input :: map() | keyword()) :: context()
  def exec(context, command_name, initial_input \\ %{}) do
    command = Map.fetch!(context.__seed_factory_meta__.commands, command_name)

    {args, context} = prepare_args(command.params, initial_input, context)

    case command.resolve.(args) do
      {:ok, resolver_output} when is_map(resolver_output) ->
        context
        |> exec_producing_instructions(command.producing_instructions, resolver_output)
        |> exec_updating_instructions(command.updating_instructions, resolver_output)
        |> exec_deleting_instructions(command.deleting_instructions)

      {:error, error} ->
        raise "Unable to execue #{inspect(command_name)} command: #{inspect(error)}"
    end
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

        raise message
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

        raise message
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

    case Map.keys(initial_input) -- Map.keys(params) do
      [] -> :noop
      keys -> raise "Input doesn't match defined params. Redundant keys found: #{inspect(keys)}"
    end

    {input, context} =
      Enum.map_reduce(params, context, fn
        {key, parameter}, context ->
          {value, context} =
            case parameter.source do
              generator when is_function(generator, 0) ->
                {Map.get_lazy(initial_input, key, generator), context}

              nil ->
                prepare_args(parameter.params, Map.get(initial_input, key, %{}), context)

              entity_name when is_atom(entity_name) ->
                case Map.fetch(initial_input, key) do
                  {:ok, value} ->
                    {value, context}

                  :error ->
                    context = produce(context, [entity_name])

                    binding_name = binding_name(context, entity_name)

                    entity = Map.fetch!(context, binding_name)
                    value = maybe_map(entity, parameter.map)
                    {value, context}
                end
            end

          {{key, value}, context}
      end)

    {Map.new(input), context}
  end

  defp maybe_map(value, map) do
    if map do
      map.(value)
    else
      value
    end
  end
end
