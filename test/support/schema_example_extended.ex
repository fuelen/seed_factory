defmodule SchemaExampleExtended do
  use SeedFactory.Schema

  include_schema SchemaExample

  command :build_conn do
    resolve(fn _ ->
      {:ok, %{conn: %{}}}
    end)

    produce :conn
  end
end
