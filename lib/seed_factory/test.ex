defmodule SeedFactory.Test do
  @moduledoc """
  A helper module for `ExUnit`.

  ## Usage

  Add the following line to your test modules:
  ```
  use SeedFactory.Test, schema: MySeedFactorySchema
  ```
  It sets up `SeedFactory` by invoking `SeedFactory.init/2` and imports `SeedFactory.rebind/3`, `SeedFactory.produce/2`, `SeedFactory.exec/3` and `SeedFactory.exec/2` functions.
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
  A macro that implicitly passes `context` and allows using `SeedFactory.produce/2` outside the `test` block.

  Basically, it creates a `setup` block and calls `SeedFactory.produce/2` inside.

  ## Examples

  ```
  produce :company

  test "my test", company: company do
    assert my_function(company)
  end
  ```

  ```
  produce [:user, :project]

  test "my test", user: user, project: project do
    assert my_function(project, user)
  end
  ```

  ```
  produce org: :org1
  produce org: :org2

  test "my test", org1: org1, org2: org2 do
    assert my_function(org2, org1)
  end
  ```
  """
  defmacro produce(entities) do
    quote bind_quoted: [entities: entities] do
      setup context do
        produce(context, unquote(entities))
      end
    end
  end
end
