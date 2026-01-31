# Changelog

## v0.7.0 (unreleased)

### Features

- Same trait can be set by multiple commands
- "Did you mean?" suggestions in compile-time errors for typos

### Compile-time Validations

- Validate referenced entities in params
- Validate circular trait dependencies
- Validate trait references in `:from` option (non-existent trait, wrong entity)

### Bug Fixes

- Fix trait transition execution order
- Fix trait resolution for commands in conflict groups
- Fix `:is_subset` conflict resolution removing commands in multiple groups
- Fix trait resolution when command produces multiple entities

### Improvements

- Major internal refactoring - extracted modules: `Context`, `Requirements`, `CommandGraph`, `Exceptions`
- Improved exception messages with better context
- Improved error reporting
- Better error message when produced entity was already produced by another command
- Hide `__spark_metadata__` from inspect output
- Compile test support files

### Dependencies

- Updated Spark and other dependencies

## v0.6.0 (2024-05-17)

### Features

- `:from` option now accepts list of traits - a trait can replace multiple parent traits:
  ```elixir
  trait :suspended, :user do
    from [:pending, :active]  # Can transition from either state
    exec :suspend_user
  end
  ```

### Bug Fixes

- Match generated args by `args_match` function when there's a conflict - fixes cases when `generate_args` has randomness
- Don't treat structs as maps in deep comparison/merging

### Improvements

- Better error message when entity was put manually into context without using SeedFactory

### Breaking Changes

- Requires Elixir ~> 1.15 (due to Spark ~> 2.1 dependency)

## v0.5.0 (2024-03-12)

### Features

- Multiple commands can produce the same entity - the first defined command becomes the default
- Automatic command selection based on trait restrictions - when traits require a specific command that produces the entity, SeedFactory automatically switches to that command

### Improvements

- Better conflict resolution when merging trait arguments
- Validate entity existence in `rebind/3` - raises `ArgumentError` for unknown entities
- Custom `Inspect` implementation for `SeedFactory.Command` for cleaner output

### Bug Fixes

- Fix producing entity with traits when it already exists without traits

### Error Messages

- Show command name when merging of args fails
- Show command name in errors when entity doesn't exist
- Helpful message when `produce` is called with 1 argument incorrectly
- Disallow nil command names

### Validations

- `:with_traits` option must be used only for parameters with type `:entity`

## v0.4.0 (2023-08-16)

### Features

- Schema composition - include other schemas using `include_schema MyApp.OtherSchema` to reuse commands and traits
- `generate_args` and `args_match` options for traits - more flexible alternative to `args_pattern` for dynamic trait matching:
  ```elixir
  trait :expired, :project do
    exec :publish_project do
      args_match(fn args -> Date.compare(Date.utc_today(), args.expiry_date) == :gt end)
      generate_args(fn -> %{start_date: Date.add(today, -22), expiry_date: Date.add(today, -1)} end)
    end
  end
  ```

### Improvements

- `:from` option is now optional for `produce` and `update` instructions - defaults to entity name
- Allow `param/1` macro without parentheses in formatter

## v0.3.0 (2023-07-23)

### Features

- Traits support - labels assigned to entities when specific commands are executed. Allows requesting entities with specific traits via `produce(context, user: [:admin, :active])`
- `pre_exec/3` - creates dependencies needed to execute a command, useful when executing the same command multiple times
- `pre_produce/2` - produces dependencies needed for specified entities

### Breaking Changes

- DSL syntax for parameters changed:
  ```elixir
  # Before (v0.2.0)
  param :name, &Faker.Person.name/0
  param :role, fn -> :normal end
  param :company, :company

  # After (v0.3.0)
  param :name, generate: &Faker.Person.name/0
  param :role, value: :normal
  param :company, entity: :company
  ```
- Renamed internal `:commands` DSL section to `:root`

### Improvements

- Friendly error when unknown command is passed to `exec`
- Raise error if unknown entity is passed to `produce`
- Allow rebinding to the same value (no longer raises)
- Compile-time validations for traits
- Exported formatter settings for `exec/1-2` and `from/1`

## v0.2.0 (2023-06-07)

### Features

- Support nested rebinding - `rebind/3` can now be nested, merging rebindings at each level and properly restoring previous state after callback completion. Raises on rebinding conflicts.

### Improvements

- Raise an error when redundant keys are passed to a command (keys not defined in params)

## v0.1.0 (2023-05-06)

Initial release.

### Features

- Schema DSL for defining entities and commands
- Command system with:
  - `produce` - for creating entities
  - `update` - for modifying entities
  - `delete` - for removing entities
- Parameter handling with support for generating values and dependencies on other entities
- Test utilities (`SeedFactory.Test`) for using in ExUnit tests
- Compile-time verification of dependencies between commands and entities
