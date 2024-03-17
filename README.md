# SeedFactory

[![CI](https://github.com/fuelen/seed_factory/actions/workflows/elixir.yml/badge.svg)](https://github.com/fuelen/seed_factory/actions/workflows/elixir.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/seed_factory.svg)](https://hex.pm/packages/seed_factory)
[![Coverage Status](https://coveralls.io/repos/github/fuelen/seed_factory/badge.svg?branch=main)](https://coveralls.io/github/fuelen/seed_factory?branch=main)

A utility for producing entities using business logic defined by your application.

The main idea of `SeedFactory` is to produce entities in tests according to your application business logic (read as context functions if you use https://hexdocs.pm/phoenix/contexts.html) whenever it is possible and avoid direct inserts to the database (opposed to `ex_machina`).
This approach allows to minimize testing of invalid states as you're not forced to keep complex database structure in your head in order to prepare test data.

See docs for details <https://hexdocs.pm/seed_factory>.

## Installation

The package can be installed by adding `seed_factory` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:seed_factory, "~> 0.5"}
  ]
end
```
