defmodule SeedFactory.Schema do
  @moduledoc """
  A schema describes how commands modify context

  This module provides a DSL for defining schemas that describe how entities should be
  created, updated, or deleted within a context using the `SeedFactory` library.

  In order to use the DSL, add the following line to your module:

      use SeedFactory.Schema

  ## Command Definition

  To define a command, use the `command` macro followed by the command name. Inside the command block, you can define various parameters, a resolution, and produce, update, and delete directives.

  ```elixir
  command :command_name do
    # Parameters, resolution, produce, update, and delete directives
  end
  ```

  ## Parameters

  Parameters define the inputs required for the command's resolver function. They can be defined using the `param` macro.

  ```elixir
  param :param_name, atom_or_function
  ```

  The `atom_or_function` can be either a static atom or a zero-arity function that generates dynamic data.

  When using an atom as the value, it refers to an entity within the context.

  ## Resolution

  The resolution defines the logic to be executed when the command is invoked. It is implemented as a resolver function inside the `resolve` block. The resolver function is an anonymous function that takes `args` as its parameter, representing the arguments provided when invoking the command.

  ```elixir
  resolve(fn args ->
    # Resolver logic
  end)
  ```

  The resolver function should return `{:ok, map}`, where map keys are atoms and values represent entities. The atom keys will be used by the `:from` option in `produce` and `update` directives.

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
  """
  use Spark.Dsl, default_extensions: [extensions: SeedFactory.DSL]
end
