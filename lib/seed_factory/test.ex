defmodule SeedFactory.Test do
  @moduledoc """
  A helper module for `ExUnit`.

  ## Usage

  Add the following line to your test modules:
  ```
  use SeedFactory.Test, schema: MySeedFactorySchema
  ```
  It sets up `SeedFactory` by invoking `SeedFactory.init/2` in `ExUnit.Callbacks.setup_all/2` block and imports the following functions:
    * `produce/1`
    * `SeedFactory.rebind/3`
    * `SeedFactory.produce/2`
    * `SeedFactory.exec/2`
    * `SeedFactory.exec/3`
    * `SeedFactory.pre_exec/2`
    * `SeedFactory.pre_exec/3`
    * `SeedFactory.pre_produce/2`
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
  A macro that implicitly passes `context` and allows usage of `SeedFactory.produce/2` outside the `test` block.

  Basically, it creates a `ExUnit.Callbacks.setup/2` block and calls `SeedFactory.produce/2` inside.

  ## Examples

  ```elixir
  produce :company

  test "my test", %{company: company} do
    assert my_function(company)
  end
  ```

  ```elixir
  produce [:user, :project]

  test "my test", %{user: user, project: project} do
    assert my_function(project, user)
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
