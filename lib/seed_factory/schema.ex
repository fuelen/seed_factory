defmodule SeedFactory.Schema do
  @moduledoc """
  A DSL for defining schemas that describe how commands modify context.

  To use the DSL, create a schema module:

      defmodule MyApp.SeedFactorySchema do
        use SeedFactory.Schema
      end

  ## Commands

  Commands are the central building block of a schema — they define how entities
  are created, updated, and deleted. Entities and traits don't exist on their own;
  they are always a result of executing a command.

  Use the `command` macro to define a command. Inside the command block,
  you can define input parameters, a resolution, and produce, update, and delete directives.

  ```elixir
  command :create_user do
    # Parameters, resolution, produce, update, and delete directives
  end
  ```

  ## Parameters

  Parameters define the inputs for the command's resolver function and how default values should be generated.
  Parameters can be defined using the `param` macro and can have an arbitrary level of nesting.

  ### Options

  * `:value` - a static default value. Applied by default as `value: nil`.
  * `:generate` - a zero-arity function that generates data. For the commands of a plan it
    runs once while the plan is built, before any command executes, and the execution reuses
    the value. Keep it to producing a value (random data, a counter): no writes to a database
    or a file.
  * `:entity` - refers to an entity within the context. If the entity is not in the context,
    SeedFactory will automatically execute a command that produces it.
  * `:with_traits` - a list of trait names or `{name, value}` pairs for parameterized traits. Requires `:entity` option.
    SeedFactory creates the entity or applies the missing traits before the command runs.
    If it cannot satisfy these requirements, the request fails before execution.

    > #### Note {: .info}
    > `:with_traits` is only used for automatic dependency resolution. If you explicitly pass
    > the entity as a parameter via `exec/3`, the traits are not validated.

  * `:map` - a function that maps the entity to another value. Requires `:entity` option.

  ```elixir
  command :create_employee do
    param :address do
      param :city, value: "Lemberg"
      param :street, generate: &random_street/0
    end

    param :paid_by, entity: :user, with_traits: [:active]
    param :office_id, entity: :office, map: & &1.id

    param :github_username
    # the line above is equivalent to
    # param :github_username, value: nil

    # resolve, produce, etc.
  end
  ```

  ## Resolution

  The `resolve` macro defines the logic executed when the command is invoked.
  The resolver is a function that takes `args` and must return either:

  * `{:ok, map}` — where keys are atoms used by `:from` option in `produce` and `update` directives
  * `{:error, reason}` — aborts execution by raising `SeedFactory.ExecError`

  ```elixir
  command :create_user do
    param :name, generate: &Faker.Person.name/0
    param :email, generate: &Faker.Internet.email/0

    resolve(fn args ->
      user = MyApp.insert_user!(args)
      {:ok, %{user: user}}
    end)

    produce :user
  end
  ```

  ## Producing Entities

  The `produce` directive specifies that the command will put a new entity to the context.

  ### Options

  * `:from` - an atom that specifies the key of the map returned by the resolver. Defaults to the entity name.

  ```elixir
  command :register_user do
    param :name, generate: &Faker.Person.name/0
    param :company, entity: :company

    resolve(fn args ->
      {user, profile} = MyApp.register_user!(args)
      {:ok, %{user: user, profile: profile}}
    end)

    produce :user
    produce :user_profile, from: :profile
  end
  ```

  ## Updating Entities

  The `update` directive modifies an existing entity within the context.

  ### Options

  * `:from` - an atom that specifies the key of the map returned by the resolver. Defaults to the entity name.

  ```elixir
  command :update_user do
    param :user, entity: :user
    param :profile, entity: :user_profile

    resolve(fn args ->
      {user, profile} = MyApp.update_user!(args.user, args.profile)
      {:ok, %{user: user, profile: profile}}
    end)

    update :user
    update :user_profile, from: :profile
  end
  ```

  ## Deleting Entities

  The `delete` directive removes an entity from the context.

  ```elixir
  command :delete_user do
    param :user, entity: :user

    resolve(fn args ->
      MyApp.delete_user!(args.user)
      {:ok, %{}}
    end)

    delete :user
  end
  ```

  ## Traits

  The `trait` directive declares a trait for an entity.
  The first argument is the trait name, the second is the entity name.

  A trait must contain an `exec` directive with the name of the command.
  Executing that command marks the entity with the trait.

  ### Options

  * `:from` - the trait or list of traits this transition replaces.
  To plan a transition, SeedFactory requires at least one source trait to be present when its command runs.
  For example, `from :pending` requires `:pending`; `from [:pending, :active]` allows either.
  Applying the new trait removes all listed source traits that are present.
  Omit `from` to add a trait without replacing another.

  ```elixir
  trait :pending, :user do
    exec :create_user
  end

  trait :active, :user do
    from :pending
    exec :activate_user
  end

  # :suspended can replace either :pending or :active
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

  When several commands can provide a trait, SeedFactory chooses one that fits
  the plan. To require a specific path, request a trait unique to that command:

  ```elixir
  # Either path can provide :active
  produce(ctx, user: [:active])

  # Force the direct path by requesting :pending_skipped trait
  produce(ctx, user: [:active, :pending_skipped])
  ```

  ## Exec step

  The `exec` directive inside a trait specifies which command must be executed
  to mark the entity with the trait.

  ### Options

  * `:args_pattern` - a map with args. If the command args match the pattern, the entity is marked with the trait.
  The pattern is also used to generate args when the entity is requested with this trait.
  * `:args_match` - a function that accepts command args and returns a boolean. Must be used with `:generate_args`.
  * `:generate_args` - a function that generates a map with args satisfying `:args_match`. Must be used with `:args_match`.

  `:args_pattern` is a simpler alternative to the `:args_match` + `:generate_args` combination.

  ### Parameterized traits

  A parameterized trait accepts a value in `produce` or `with_traits`.
  Put `_` in `:args_pattern` where the command should receive that value:

  ```elixir
  command :create_user do
    param :age, value: 21

    resolve(fn args -> MyApp.Users.create_user(args) end)

    produce :user
  end

  trait :age, :user do
    exec :create_user, args_pattern: %{age: _}
  end

  produce(ctx, user: [age: 18])
  ```

  Here, `produce` passes `age: 18` to `:create_user`. After the command runs,
  SeedFactory records `{:age, 18}` in the user's traits. A direct `exec/3` call
  records the trait in the same way, using the value from the command arguments.

  A dependency can require the same value through `with_traits`:

  ```elixir
  param :user, entity: :user, with_traits: [age: 18]
  ```

  Other fields in the pattern must match too. For example,
  `%{age: _, role: :admin}` records the trait only when the command receives
  `role: :admin`.

  The rules:

  * Each parameterized trait uses exactly one `_` placeholder as a map value,
    for example `%{age: _}` or `%{settings: %{locale: _}}`.
  * A parameterized trait requires one value, which can be any Elixir term.
    Use separate traits for separate arguments.
  * Values are compared with `===`, so `18` and `18.0` are different values.
  * `from` can only name ordinary traits. A parameterized trait can use `from`
    to replace an ordinary trait; its own previous value is replaced automatically.
  * `:as` is reserved for rebinding and cannot name a parameterized trait.

  #### Existing entities and value changes

  Requesting a value already recorded in the entity's traits does not run
  another command. To change the value, add an update command and another
  declaration of the same trait to the schema above:

  ```elixir
  command :set_age do
    param :user, entity: :user
    param :age

    resolve(fn args -> MyApp.Users.set_age(args.user, args.age) end)

    update :user
  end

  trait :age, :user do
    exec :set_age, args_pattern: %{age: _}
  end

  ctx = produce(ctx, user: [age: 18]) # runs :create_user
  ctx = produce(ctx, user: [age: 18]) # runs nothing
  ctx = produce(ctx, user: [age: 21]) # runs :set_age on the same user
  ```

  After the update, `{:age, 21}` replaces `{:age, 18}` in the user's traits.
  Without an update command for the trait, requesting a different value fails
  before execution.

  ### Ordinary trait matching and argument generation

  Use `args_pattern` when a trait requires fixed argument values:

  ```elixir
  trait :admin, :user do
    exec :create_user, args_pattern: %{role: :admin}
  end

  trait :normal, :user do
    exec :create_user, args_pattern: %{role: :normal}
  end
  ```

  The equivalent declarations using functions are:

  ```elixir
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

  Use `args_match` and `generate_args` when the condition cannot be expressed
  with fixed values. `args_match` checks whether the arguments satisfy the trait;
  `generate_args` supplies arguments that satisfy it when the trait is requested.
  For example, an expiration check depends on today's date:

  ```elixir
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

  `generate_args` runs once during planning, before any command executes.
  The command then uses those generated arguments. Keep this function free of
  database and file writes. SeedFactory also evaluates `args_match` during
  planning when the required arguments are known; if it needs an entity that
  has not been created yet, the check waits until that entity is available.

  ## Splitting large schemas with fragments

  SeedFactory uses [Spark](https://hexdocs.pm/spark) for its DSL. Spark provides a mechanism
  called `Spark.Dsl.Fragment` that allows splitting a large DSL module into multiple files.

  When a schema grows large, you can extract groups of related commands and traits into fragments.
  Each fragment can contain commands and traits, and they are merged into the main schema at compile time.

  ```elixir
  defmodule MyApp.SeedFactorySchema.UserCommands do
    use Spark.Dsl.Fragment,
      of: SeedFactory.Schema

    command :create_user do
      param :name, generate: &Faker.Person.name/0
      param :role, value: :normal

      resolve(fn args -> MyApp.Users.create_user(args) end)

      produce :user
    end

    command :activate_user do
      param :user, entity: :user, with_traits: [:pending]

      resolve(fn args ->
        {:ok, %{user: MyApp.Users.activate_user!(args.user)}}
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
  end

  defmodule MyApp.SeedFactorySchema do
    use SeedFactory.Schema,
      fragments: [MyApp.SeedFactorySchema.UserCommands]

    # other commands go here
  end
  ```

  Fragments can reference entities from other fragments or from the main schema —
  dependency resolution works across all of them.

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

  defmacro __using__(opts) do
    spark = super(opts)

    quote do
      unquote(spark)
      import SeedFactory.DSL.Root.Trait, except: [trait: 2, trait: 3]
      import SeedFactory.TraitDSL, only: [trait: 2, trait: 3]
    end
  end
end
