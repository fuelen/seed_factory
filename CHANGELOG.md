# Changelog

## v0.10.1 (2026-09-29)

### Bug fixes

- Fix planned `from` transitions using a source trait that an earlier command
  had already removed.
- Fix transitions incorrectly rejected when their source trait was added by
  a later invocation of the same command.

## v0.10.0 (2026-09-27)

### Features

- Add parameterized traits: declare `args_pattern: %{age: _}` and pass a value
  with `produce(ctx, user: [:active, age: 18])`. Parameterized traits also work
  in `with_traits`, and their values are tracked after both `produce` and `exec`.

### Changes

- Validate `with_traits` references at schema compilation, reporting invalid
  references with `Spark.Error.DslError` instead of failing during planning.
- Reject conflicting `:as` bindings and malformed trait entries in `produce`
  and `pre_produce` with `ArgumentError` instead of silently ignoring them.
  Unknown traits raise `SeedFactory.UnknownTraitError`.
- Report conflicting traits across repeated entity entries with
  `SeedFactory.TraitRestrictionConflictError`, consistently with a single entry,
  instead of `SeedFactory.TraitResolutionError`.

### Bug fixes

- Apply traits listed after `:as` in `produce` and `pre_produce` requests.
- Fix `args_pattern` matching against structs and nested patterns against
  scalar arguments, which previously raised exceptions.
- Remove all occurrences of a trait during a `from` transition, including
  traits applied by multiple commands.

### Requirements

- Raise the minimum Spark version to 2.7.3 (`~> 2.7 and >= 2.7.3`).

## v0.9.0 (2026-09-11)

The planning behind `produce`, `pre_produce`, `exec` and `pre_exec` was rebuilt.

### What you can rely on

- After `produce`, every requested entity is in the context, with every requested trait. A request that cannot be honoured fails before anything runs. Previously such a request could return a context silently missing the entity or the trait, or crash halfway through the execution.
- Plans that need an alternative are found: another command producing the entity, another route to a trait, a command re-producing an entity after a deleting command consumed it. Previously these requests failed with a false circular-dependency or trait error.
- Entities already in the context are respected: a command re-producing one needs a deleting command in between, and the commands consuming, deleting and re-producing it run in a valid order. Previously that order could depend on command names and crash or hand a command an entity in the wrong state.
- A command runs only once the entities its params name exist and carry the traits their `with_traits` ask for at that moment. Previously a planned command could receive an entity a later-planned command had already stripped of the trait, or one it had deleted.
- A request is a set: the plan does not depend on the order of its entries or of the traits within an entry. Previously the entity named first could pick a producer the others then had to live with, and the same request written in another order produced different side entities and traits.
- `pre_produce` prepares the dependencies of the requested entities even when producing everything in one `produce` call would be impossible, and never consumes an entity the request names.

### What changed for schemas

- The `generate` functions of params and the `generate_args` functions of trait declarations run once, while the plan is built and before any command executes; the execution reuses the values. Keep them to producing values (random data, counters), without writes to a database or a file.
- A trait declared with `from` replaces the named trait, and a command that later asks for the replaced trait through `with_traits` is refused, where it used to run. A trait that adds a property without leaving the previous state is declared without `from`.

### Requirements

- Elixir 1.19 or later. The previous minimum was 1.15.

### Errors

A refused request explains every candidate it rejected:

```
cannot produce entity :contract: no candidate command fits the plan
- :sign_contract would duplicate existing :contract_copy (rebind or delete it first)
- :import_contract would duplicate existing :approval (rebind or delete it first)
```

A plan that would end without a requested trait raises `SeedFactory.MissingRequestedTraitError`, naming the command whose transition removes the trait.

`SeedFactory.ConflictingTraitsError` is gone. Two requested traits whose commands would both produce the same entity are refused with the reason `also produces :x, already produced by :y in this plan`. A request one command can serve on its own now succeeds, where the removed check refused it.

A request asking for a trait together with one that replaces it is refused naming the request. The message used to name a `nil` command.

### Bug fixes

- A requested trait consumed by a transition declared with a `from` list was silently skipped. It now raises, like a transition declared with a single `from`.
- `with_traits` on an entity param accepted an entity that had gone through the required trait and lost it. It now raises, or uses another candidate when one exists.
- Trait resolution gave up when the first option of a `from` list could not be satisfied. The options are now tried in the declared order.
- A trait declared on several commands was reported as a mismatch when one executed command did not add it while another did. Every executed declaration is now reported.
- Input for a param nested in a `param ... do ... end` container did not cover the dependency: the command producing it still ran.
- The compile-time trait cycle check missed a cycle through a `from` edge of a shadowed declaration. Such a schema compiled and could hang `produce`.

## v0.8.2 (2026-08-18)

### Bug Fixes

- Fix trait resolution depending on the order of traits in a `produce` request. A trait declared on a single command now wins conflict resolution regardless of its position in the list, and conflicting trait requests raise `SeedFactory.TraitResolutionError` instead of silently producing the entity through another command.
- Fix missing execution-order edges after conflict resolution removes a producer another node depended on. Could surface as `KeyError` depending on the topological sort tie-break.
- Fix `produce` silently returning an incomplete context when the selected commands form a circular dependency. Now raises `SeedFactory.CircularDependencyError` naming the commands.
- Fix `with_traits` on an entity param being ignored when selecting the producer of an absent dependency while the demanding command was still in unresolved conflict groups. Such a demand now wins conflict resolution once the demanding command settles in the plan, and expires when that command leaves it.

## v0.8.1 (2026-08-17)

### Bug Fixes

- Fix `FunctionClauseError` when producing a second instance of an entity via rebinding and every producing command would duplicate an existing entity. Now raises `SeedFactory.EntityAlreadyExistsError` naming the entity that must be rebound.
- Fix missing execution-order edges for commands that are re-executed under rebinding. Could surface as `KeyError` depending on topological sort tie-break.
- Fix args of a trait declared on several commands leaking into the command that did not declare them. `produce` then failed with "Input doesn't match defined params".

## v0.8.0 (2026-03-29)

### Features

- Add `SeedFactory.ExecError` — structured exception for resolver failures with execution plan, trails, and current traits
- Add execution history to meta (`execution_history`) that records all produce/exec calls with caller, rebinding, and executed commands
- Add `Context.track_execution/3` for automatic execution tracking
- Add custom `Inspect` for SeedFactory.Execution with compact `#execution[...]` format

### Breaking Changes

- Resolver `{:error, error}` now raises `SeedFactory.ExecError` instead of `RuntimeError`

### Performance

- Replace `libgraph` dependency with inline topological sort
- Optimize compile-time trait indexing
- Fix quadratic list accumulation in `scan_subsequent_traits`

### Improvements

- Improved documentation for core functions, `SeedFactory.Schema`, and `SeedFactory.Test` modules

## v0.7.1 (2026-03-26)

### Bug Fixes

- Fix trait-resolved node being overwritten by later conflict resolution
- Fix warning from ex_docs
- Fix flaky test

### Improvements

- Skip coverage for test/support files
- Update dependencies

## v0.7.0 (2026-01-31)

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
- Custom Inspect implementation for SeedFactory.Command for cleaner output

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
