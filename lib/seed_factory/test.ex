defmodule SeedFactory.Test do
  @moduledoc """
  Integrates `SeedFactory` with `ExUnit`.

  ## Usage

  Add the following line to your test modules:
  ```elixir
  use SeedFactory.Test, schema: MySeedFactorySchema
  ```

  This will:
  * initialize the schema via `SeedFactory.init/2` in a `setup_all` callback
  * import `SeedFactory` functions:
    * `SeedFactory.exec/3`
    * `SeedFactory.produce/2`
    * `SeedFactory.rebind/3`
    * `SeedFactory.pre_exec/3`
    * `SeedFactory.pre_produce/2`
  * import the `produce/1` macro (see below)
  """
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      import SeedFactory,
        only: [rebind: 3, produce: 2, exec: 2, exec: 3, pre_exec: 2, pre_exec: 3, pre_produce: 2]

      import SeedFactory.Test

      setup_all context do
        schema = unquote(opts[:schema])

        SeedFactory.init(context, schema)
      end
    end
  end

  @doc """
  A macro for producing entities outside of `test` blocks.

  Generates a `setup` callback that calls `SeedFactory.produce/2`, so the entities
  are available in all tests within the scope. Accepts the same arguments as `produce/2`. This:

      produce [:company, user: [:active, :admin]]

  is equivalent to:

      setup context do
        produce(context, [:company, user: [:active, :admin]])
      end

  Can only be called outside of `test` blocks. For producing entities inside a test,
  use `SeedFactory.produce/2` directly.

  ## Examples

  ```elixir
  produce :company

  test "my test", %{company: company} do
    assert my_function(company)
  end
  ```

  ```elixir
  produce [:company, user: [:active, :admin, as: :active_admin]]

  test "my test", %{company: company, active_admin: admin} do
    assert my_function(company, admin)
  end
  ```

  ```elixir
  produce org: :org1
  produce org: :org2

  test "my test", %{org1: org1, org2: org2} do
    assert my_function(org2, org1)
  end
  ```
  """

  @spec produce(
          SeedFactory.entity_name()
          | [
              SeedFactory.entity_name()
              | SeedFactory.rebinding_rule()
              | {SeedFactory.entity_name(), [trait_name :: atom() | {:as, rebind_as :: atom()}]}
            ]
        ) :: Macro.t()
  defmacro produce(data) do
    if __CALLER__.function != nil do
      raise ArgumentError,
        message:
          "produce/1 cannot be called in runtime, probably you forgot to pass context as an argument"
    end

    quote bind_quoted: [data: data] do
      setup context do
        produce(context, unquote(data))
      end
    end
  end
end
