<p align="center"><img src="logo.svg" alt="seed_factory" height="200px"></p>

# SeedFactory

[![CI](https://github.com/fuelen/seed_factory/actions/workflows/elixir.yml/badge.svg)](https://github.com/fuelen/seed_factory/actions/workflows/elixir.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/seed_factory.svg)](https://hex.pm/packages/seed_factory)
[![Coverage Status](https://coveralls.io/repos/github/fuelen/seed_factory/badge.svg?branch=main)](https://coveralls.io/github/fuelen/seed_factory?branch=main)
[![Documentation](https://img.shields.io/badge/documentation-gray)](https://hexdocs.pm/seed_factory)

A toolkit for test data generation.

The main idea of `SeedFactory` is to generate data in tests according to your application business logic (read as context functions if you use [Phoenix Contexts](https://hexdocs.pm/phoenix/contexts.html)) whenever possible and avoid direct inserts to the database (as opposed to `ex_machina`).
This approach allows you to minimize testing of invalid states as you're not forced to keep complex database structure in your head in order to prepare test data.
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

This section provides a couple of examples of what the API of the library looks like. For more comprehensive explanations please refer to [docs](https://hexdocs.pm/seed_factory). **README is NOT the primary source of documentation.**

To use the library, define a schema with commands that describe the processes of your application. When a command is executed it modifies the context by producing/updating/deleting entities.

There is a concept of traits. Think about them as labels which are assigned to produced/updated entities when specific commands with specific arguments are executed.

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

### Usage example

```elixir
import SeedFactory

context = %{}
# Put metadata about the schema to the context with the help of init/2 function
context = init(context, MyApp.SeedFactorySchema)

# Now, we can execute a command with automatically generated args using exec/2
%{company: _} = exec(context, :create_company)

# Arguments can be passed explicitly using exec/3
%{company: _, user: _, profile: _} =
  context
  |> exec(:create_company, name: "GitHub")
  |> exec(:create_user, name: "John Doe")
  |> exec(:activate_user)

# Dependent entities are produced automatically if there is no such entity in the context.
# In this example, :create_company will be executed implicitly, because :create_user depends on :company
%{company: _, user: _} = exec(context, :create_user)

# If you're fine with generated arguments, then you can use produce/2 to specify
# desired entities and the chain of corresponding commands will be executed automatically
%{company: _company} = produce(context, :company)
%{user: _user, company: _company} = produce(context, [:company, :user])

# Rebind entities to other names
%{profile1: _, user1: _} = produce(context, user: :user1, profile: :profile1)

# Specify traits
%{user: _user} = produce(context, user: [:admin, :active])

# The command above is an alternative to
%{user: _user} =
  context
  |> exec(:create_user, role: :admin)
  |> exec(:activate_user)
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
ctx = produce(ctx, user: [:pending, :active])
IO.inspect(ctx.__seed_factory_meta__)
# #SeedFactory.Meta<
#   current_traits: %{user: [:active, :normal]},
#   trails: %{user: #trail[create_user: +[:pending, :normal] -> activate_user: +[:active] -[:pending]]}
# >
```
