defmodule SchemaExampleExtended do
  use SeedFactory.Schema

  include_schema SchemaExample

  command :build_conn do
    resolve(fn _ ->
      {:ok, %{conn: %{}}}
    end)

    produce :conn, from: :conn
  end

  command :create_session do
    param :user, entity: :user, with_traits: [:active]
    param :conn, entity: :conn

    resolve(fn %{user: user, conn: conn} ->
      {:ok, Map.put(conn, :logged_in_as, user.id)}
    end)

    update :conn, from: :conn
  end
end
