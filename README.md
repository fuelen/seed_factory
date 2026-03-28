<p align="center"><img src="logo.svg" alt="seed_factory" height="200px"></p>

# SeedFactory

[![CI](https://github.com/fuelen/seed_factory/actions/workflows/elixir.yml/badge.svg)](https://github.com/fuelen/seed_factory/actions/workflows/elixir.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/seed_factory.svg)](https://hex.pm/packages/seed_factory)
[![Coverage Status](https://coveralls.io/repos/github/fuelen/seed_factory/badge.svg?branch=main)](https://coveralls.io/github/fuelen/seed_factory?branch=main)
[![Documentation](https://img.shields.io/badge/documentation-gray)](https://hexdocs.pm/seed_factory)

A toolkit for test data generation.

The main idea of `SeedFactory` is to generate data in tests according to your application business logic (read as context functions if you use [Phoenix Contexts](https://hexdocs.pm/phoenix/contexts.html)) whenever possible and avoid direct inserts to the database (as opposed to `ex_machina`).
This approach allows you to minimize testing of invalid states as you're not forced to keep complex database structure in your head in order to prepare test data.
Even in cases where calling business logic functions is impractical (e.g. for performance reasons), SeedFactory serves as a centralized hub for test data creation, ensuring a consistent approach across your test suite.
Dependent entities are resolved and created automatically, so you can focus on what matters for your test.
The library is completely agnostic to the database toolkit.

See docs for details <https://hexdocs.pm/seed_factory>.

## Installation

The package can be installed by adding `seed_factory` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:seed_factory, "~> 0.7"}
  ]
end
```

## Overview

This section provides a brief overview of the API. For comprehensive explanations please refer to [docs](https://hexdocs.pm/seed_factory).

To use the library, define a schema with commands that describe the processes of your application. When a command is executed it modifies the context by producing/updating/deleting entities.

Entities can have traits — labels that describe how an entity was created or what state it is in. Traits can build on each other using `from` (e.g. `:active` requires `:pending` first) and can be tied to specific argument values using `args_pattern`.

### Schema example

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

### Usage example

```elixir
import SeedFactory

context = %{}
context = init(context, MyApp.SeedFactorySchema)

# Execute a command with automatically generated args
%{company: _} = exec(context, :create_company)

# Arguments can be passed explicitly
%{company: _, user: _, profile: _} =
  context
  |> exec(:create_company, name: "GitHub")
  |> exec(:create_user, name: "John Doe")
  |> exec(:activate_user)

# Dependencies are resolved automatically — :create_company runs implicitly
%{company: _, user: _} = exec(context, :create_user)

# produce/2 executes the full chain of commands for requested entities
%{company: _company} = produce(context, :company)
%{user: _user, company: _company} = produce(context, [:company, :user])

# Rebind entities to other names
%{profile1: _, user1: _} = produce(context, user: :user1, profile: :profile1)

# Specify traits — these two are equivalent
%{user: _user} = produce(context, user: [:admin, :active])

%{user: _user} =
  context
  |> exec(:create_user, role: :admin)
  |> exec(:activate_user)

# Combine traits with rebinding using :as option
%{active_admin: _} = produce(context, user: [:admin, :active, as: :active_admin])
```

Usage with `ExUnit`:
```elixir
defmodule MyApp.MyTest do
  use ExUnit.Case
  use SeedFactory.Test, schema: MyApp.SeedFactorySchema

  describe "produce/1 macro" do
    produce [:company, user: [:active, :admin, as: :active_admin]]

    test "inspect data", %{company: company, active_admin: active_admin} do
      dbg(company)
      dbg(active_admin)
    end
  end


  describe "produce/2 and exec/3 functions" do
    test "demo #1", ctx do
      ctx =
        ctx
        |> exec(:create_company, name: "GitHub")
        |> produce(user: [:normal, :active])

      dbg(ctx)
    end

    test "demo #2", ctx do
      ctx
      |> produce(company: :company1, user: :user1, profile: :profile1)
      |> produce(company: :company2, user: :user2, profile: :profile2)
      |> dbg()
    end

    test "demo #3", ctx do
      ctx = produce(ctx, :company)
      ctx1 = ctx |> exec(:create_user, name: "John")
      ctx2 = ctx |> exec(:create_user, name: "Jane") |> exec(:activate_user)

      dbg(ctx1)
      dbg(ctx2)
    end
  end
end
```

### Advanced features

#### Reusing dependencies with `pre_exec` / `pre_produce`

Create dependencies without executing the command itself. Useful when you need multiple variations sharing the same base:

```elixir
# Create company without creating user
ctx = pre_produce(ctx, :user)

# Now create multiple users in the same company
%{user: user1} = produce(ctx, :user)
%{user: user2} = produce(ctx, :user)
# Both users belong to the same company
```

#### Dynamic trait matching with `args_match` and `generate_args`

For complex trait conditions that can't be expressed with simple `args_pattern`, use function-based matching:

```elixir
trait :not_expired, :subscription do
  exec :create_subscription do
    args_match(fn args -> Date.compare(args.expires_at, Date.utc_today()) == :gt end)
    generate_args(fn -> %{expires_at: Date.add(Date.utc_today(), 30)} end)
  end
end
```

#### Trail tracking

The context maintains a history of how each entity was created and modified. Useful for debugging:

```elixir
ctx = produce(ctx, user: [:admin, :active])
IO.inspect(ctx.__seed_factory_meta__)
# #SeedFactory.Meta<
#   current_traits: %{company: [], profile: [], user: [:admin, :active]},
#   trails: %{
#     company: #trail[:create_company],
#     profile: #trail[:create_user],
#     user: #trail[create_user: +[:pending, :admin] -> activate_user: +[:active] -[:pending]]
#   },
#   execution_history: [
#     #execution[produce(user: [:admin, :active]): create_company → create_user → activate_user]
#   ],
#   ...
# >
```
