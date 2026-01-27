defmodule SeedFactory.Schema do
  @moduledoc """
  A schema describes how commands modify context

  This module provides a DSL for defining schemas that describe how entities should be
  created, updated, or deleted within a context using the `SeedFactory` library.

  In order to use the DSL, create a schema module with the following content:

      defmodule MyApp.SeedFactorySchema do
        use SeedFactory.Schema
      end

  ## Command Definition

  Command is the first thing that should be defined in the schema.
  To define a command, use the `command` macro followed by the command name. Inside the command block,
  you can define input parameters, a resolution, and produce, update, and delete directives.

  ```elixir
  command :create_user do
    # Parameters, resolution, produce, update, and delete directives
  end
  ```

  ## Parameters

  Parameters define the inputs required for the command's resolver function and how default values should be generated.
  Parameter can be defined using the `param` macro and can have an arbitrary level of nesting.

  ### Options

  * `:value` - a static default value. Applied by default as `value: nil`.
  * `:generate` - an anonymous function that generates data.
  * `:entity` - refers to an entity within the context.
  * `:with_traits` - a list of atoms with trait names. Can be applied only if `:entity` option is present.
    This option is used only for automatic dependency resolution - when the entity doesn't exist in the context,
    SeedFactory will produce it with the specified traits. If you explicitly pass the entity as a parameter,
    the traits are not validated.
  * `:map` - an anonymous function that allows mapping an entity to another value. Can be applied only if `:entity` option is present.

  ```elixir
  param :address do
    param :city, value: "Lemberg"
    param :street, generate: &random_street/0
  end

  param :paid_by, entity: :user, with_traits: [:active]
  param :office_id, entity: :office, map: & &1.id

  param :github_username
  # the line above is equivalent to
  # param :github_username, value: nil
  ```

  ## Resolution

  The resolution defines the logic to be executed when the command is invoked. It is implemented as a resolver function inside the `resolve` macro.
  The resolver function is an anonymous function that takes `args` as its parameter.

  It should return `{:ok, map}`, where map keys are atoms and values represent entities.
  The atom keys will be used by the `:from` option in `produce` and `update` directives.

  `{:error, reason}` will abort the command execution by raising an exception.

  ```elixir
  resolve(fn args ->
    user = MyApp.insert_user!(args)
    {:ok, %{user: user}}
  end)
  ```

  ## Producing Entities

  The `produce` directive specifies that the command will put a new entity to the context. It takes two arguments: the name of the entity being produced and options.

  ### Options

  * `:from` - an atom that specifies the key of the map returned by the resolver. Defaults to specified entity name (first argument)

  ```elixir
  produce :entity_name, from: :source_key
  ```

  ```elixir
  resolve(fn args ->
    {user, profile} = MyApp.register_user!(args)
    {:ok, %{user: user, profile: profile}}
  end)

  produce :user
  produce :user_profile, from: :profile
  ```

  ## Updating Entities

  The `update` directive modifies an existing entity within the context. It takes two arguments: the name of the entity being updated and options.

  ### Options

  * `:from` - an atom that specifies the key of the map returned by the resolver. Defaults to specified entity name (first argument)

  ```elixir
  update :entity_name, from: :source_key
  ```

  ```elixir
  resolve(fn args ->
    {user, profile} = MyApp.update_user!(args)
    {:ok, %{user: user, profile: profile}}
  end)

  update :user
  update :user_profile, from: :profile
  ```

  ## Deleting Entities

  The `delete` directive removes an entity from the context.

  ```elixir
  resolve(fn args ->
    MyApp.delete_user!(args.user_id)
    {:ok, %{}}
  end)

  delete :user
  ```

  ## Traits

  The `trait` directive declares a trait for an entity.
  The first argument is trait name, the second is entity name.

  A trait must contain an `exec` directive with the name of the command. Execution of the specified command marks
  entity with the trait.

  ### Options

  * `:from` - an atom or a list of atoms that point to the traits that should be replaced with the new one. This is useful for different kinds of
  status transitions.


  ```elixir
  trait :pending, :user do
    exec :create_user
  end

  trait :active, :user do
    from :pending
    exec :activate_user
  end

  trait :suspended, :user do
    from [:pending, :active]
    exec :suspend_user
  end

  # execute :create_user command
  produce(ctx, user: [:pending])

  # execute :create_user -> :activate_user
  produce(ctx, user: [:active])

  # execute :create_user -> :suspend_user
  produce(ctx, user: [:suspended])

  # execute :create_user -> :activate_user -> :suspend_user
  ctx |> produce(user: [:active]) |> produce(user: [:suspended])
  ```

  ### Same trait from multiple commands

  The same trait can be defined multiple times with different commands. This is useful when the same state
  can be reached through different paths in your business logic:

  ```elixir
  # User can become :active through a state transition...
  trait :active, :user do
    from :pending
    exec :activate_user
  end

  # ...or directly via a command that creates an already-active user
  trait :active, :user do
    exec :create_active_user
  end

  # Unique marker for the direct path
  trait :pending_skipped, :user do
    exec :create_active_user
  end
  ```

  When you request an entity with a trait that can be set by multiple commands, SeedFactory picks
  the first declared command by default. To force a specific path, request a trait that is unique
  to that command:

  ```elixir
  # SeedFactory picks the first declared command by default
  produce(ctx, user: [:active])

  # Force the direct path by requesting :pending_skipped trait
  produce(ctx, user: [:active, :pending_skipped])
  ```

  ## Exec step

  The `exec` directive is required when declaring a trait and is used for specifying what should be executed in order
  to mark entity with the trait

  ### Options

  * `:args_match` - a function which accepts command args and must return a boolean. Must be used with `:generate_args` option.
  If the function returns `true`, then the entity will be marked with the trait.
  * `:generate_args` - a function which generates a map with args. Must be used with `:args_match` option. The function generates args which satisfy
  validation in `:args_match` option and is used when the entity is requested with the trait.
  * `:args_pattern` - a map with args. This option is less verbose (and limited in functionality) alternative to the combination of `:args_match` and `:generate_args` options.
  If specified, then entity will be marked with the trait only when command args match the pattern. Also, the pattern will be used as a replacement to `:generate_args` invocation.

  ```elixir
  # all three instructions below are equal
  exec :create_user
  exec :create_user, args_pattern: %{}
  exec :create_user, generate_args: fn -> %{} end, args_match: fn _args -> true end
  ```

  ```elixir
  trait :admin, :user do
    exec :create_user, args_pattern: %{role: :admin}
  end

  trait :normal, :user do
    exec :create_user, args_pattern: %{role: :normal}
  end

  # the same using the combination of `:args_match` and `:generate_args`
  trait :admin, :user do
    exec :create_user do
      generate_args(fn -> %{role: :admin} end)
      args_match(&match?(%{role: :admin}, &1))
    end
  end

  trait :normal, :user do
    exec :create_user do
      generate_args(fn -> %{role: :normal} end)
      args_match(&match?(%{role: :normal}, &1))
    end
  end
  ```

  ```elixir
  # an example which shows what is possible with `:args_match` + `:generate_args`
  # but not with `:args_pattern`

  trait :not_expired, :project do
    exec :publish_project do
      args_match(fn args -> Date.compare(Date.utc_today(), args.expiry_date) in [:lt, :eq] end)

      generate_args(fn ->
        today = Date.utc_today()
        %{start_date: today, expiry_date: Date.add(today, 21)}
      end)
    end
  end

  trait :expired, :project do
    exec :publish_project do
      args_match(fn args -> Date.compare(Date.utc_today(), args.expiry_date) == :gt end)

      generate_args(fn ->
        today = Date.utc_today()
        %{start_date: Date.add(today, -22), expiry_date: Date.add(today, -1)}
      end)
    end
  end
  ```

  ## Include schemas

  It is possible to include multiple schemas into a new schema in order to reuse everything that is declared in specified modules.

  ```elixir
  defmodule MyAppWeb.SeedFactorySchema do
    use SeedFactory.Schema

    include_schema MyApp.SeedFactorySchema

    # Web-specific stuff goes here. You may need such a separation of modules
    # if you have an umbrella project and web is a separate app
    command :build_conn do
      resolve(fn _ ->
        conn =
          Phoenix.ConnTest.build_conn()
          |> Plug.Conn.put_private(:phoenix_endpoint, MyAppWeb.Endpoint)
        {:ok, %{conn: conn}}
      end)

      produce :conn
    end

    command :create_user_session do
      param :user, entity: :user, with_traits: [:active]
      param :conn, entity: :conn, with_traits: [:unauthenticated]

      resolve(fn args ->
        {:ok, %{conn: MyAppWeb.Session.init_user_session(args.conn, args.user)}}
      end)

      update :conn
    end

    trait :unauthenticated, :conn do
      exec :build_conn
    end

    trait :user_session, :conn do
      from :unauthenticated
      exec :create_user_session
    end
  end
  ```
  """
  use Spark.Dsl, default_extensions: [extensions: SeedFactory.DSL], opts_to_document: []
end
