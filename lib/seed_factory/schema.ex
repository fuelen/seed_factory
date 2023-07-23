defmodule SeedFactory.Schema do
  @moduledoc """
  A schema describes how commands modify context

  This module provides a DSL for defining schemas that describe how entities should be
  created, updated, or deleted within a context using the `SeedFactory` library.

  In order to use the DSL, add the following line to your module:

      use SeedFactory.Schema

  ## Command Definition

  Command is the first thing that should be defined in the schema.
  To define a command, use the `command` macro followed by the command name. Inside the command block,
  you can define various parameters, a resolution, and produce, update, and delete directives.

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
  * `:map` - an anonymous function that allows mapping an entity to another value. Can be applied only if `:entity` option is present.

  One of these options should always be specified: `:value`, `:generate`, `:entity`.

  ```elixir
  param :address do
    param :city, value: "Lemberg"
    param :street, generate: &random_street/0
  end

  param :paid_by, entity: :user, with_traits: [:active]
  param :office_id, entity: :office, map: & &1.id
  ```

  ## Resolution

  The resolution defines the logic to be executed when the command is invoked. It is implemented as a resolver function inside the `resolve` macro.
  The resolver function is an anonymous function that takes `args` as its parameter.

  It should return `{:ok, map}`, where map keys are atoms and values represent entities.
  The atom keys will be used by the `:from` option in `produce` and `update` directives.

  `{:error, reason}` will raise an exception.

  ```elixir
  resolve(fn args ->
    user = MyApp.insert_user!(args)
    {:ok, %{user: user}}
  end)
  ```

  ## Producing Entities

  The `produce` directive specifies that the command will put a new entity to the context. It takes two arguments: the name of the entity being produced and options.

  ### Options

  * `:from` - an atom that specifies the key of the map returned by the resolver.

  ```elixir
  produce :entity_name, from: :source_key
  ```

  ## Updating Entities

  The `update` directive modifies an existing entity within the context. It takes two arguments: the name of the entity being updated and options.

  ### Options

  * `:from` - an atom that specifies the key of the map returned by the resolver.

  ```elixir
  update :entity_name, from: :source_key
  ```

  ## Deleting Entities

  The `delete` directive removes an entity from the context.

  ```elixir
  delete :entity_name
  ```

  It is used to delete an entity from the context.

  ## Traits

  The `trait` directive declares a trait for an entity.
  The first argument is trait name, the second is entity name.

  A trait must contain an `exec` directive with the name of the command. Execution of the specified command marks
  entity with the trait.

  ### Options

  * `:from` - an atom that points to the trait that should be replaced with the new one. This is useful for different kinds of
  status transitions.


  ```elixir
  trait :pending, :user do
    exec :create_user
  end
  ```

  ```elixir
  trait :active, :user do
    from :pending
    exec :activate_user
  end
  ```

  ## Exec step

  The `exec` directive is required when declaring a trait and is used for specifying what should be executed in order
  to mark entity with the trait

  ### Options

  * `:args_pattern` - a map with args. If specified, then entity will be marked with the trait only when command args match the pattern.

  ```elixir
  exec :create_user, args_pattern: %{role: :admin}
  ```

  ```elixir
  exec :create_user, args_pattern: %{role: :normal}
  ```

  """
  use Spark.Dsl, default_extensions: [extensions: SeedFactory.DSL]
end
