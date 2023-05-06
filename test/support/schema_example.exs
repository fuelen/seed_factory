defmodule SchemaExample do
  use SeedFactory.Schema

  defmodule Org, do: defstruct([:id, :name, :address])
  defmodule Office, do: defstruct([:id, :name, :org_id])
  defmodule User, do: defstruct([:id, :name, :office_id, :status])
  defmodule Project, do: defstruct([:id, :name, :office_id, :draft?])

  def random_string do
    "random-string-#{:erlang.unique_integer()}"
  end

  def get_id(map) do
    map.id
  end

  def gen_id do
    :erlang.unique_integer([:positive])
  end

  command :raise_exception do
    resolve(fn _args ->
      raise "BOOM"
    end)

    update :user, from: :user
  end

  command :resolve_with_error do
    resolve(fn _args ->
      {:error, %{message: "OOPS", other_key: :data}}
    end)

    update :user, from: :user
  end

  command :create_org do
    param :name, &random_string/0

    param :address do
      param :city, &random_string/0
      param :country, &random_string/0
    end

    resolve(fn args ->
      org = %Org{name: args.name, address: args.address, id: gen_id()}
      {:ok, %{org: org}}
    end)

    produce :org, from: :org
  end

  command :create_office do
    param :name, &random_string/0
    param :org, :org

    resolve(fn args ->
      office = %Office{name: args.name, org_id: args.org.id, id: gen_id()}
      {:ok, %{office: office}}
    end)

    produce :office, from: :office
  end

  command :create_draft_project do
    param :name, &random_string/0
    param :office, :office

    resolve(fn args ->
      project = %Project{name: args.name, draft?: true, office_id: args.office.id, id: gen_id()}
      {:ok, %{project: project}}
    end)

    produce :draft_project, from: :project
  end

  command :publish_project do
    param :project, :draft_project

    resolve(fn args -> {:ok, %{project: %{args.project | draft?: false}}} end)

    produce :project, from: :project
    delete :draft_project
  end

  command :create_user do
    param :name, &random_string/0
    param :office_id, :office, map: &get_id/1

    resolve(fn args ->
      user = %User{name: args.name, office_id: args.office_id, id: gen_id(), status: :pending}
      {:ok, %{user: user}}
    end)

    produce :user, from: :user
  end

  command :activate_user do
    param :user, :user

    resolve(fn args -> {:ok, %{user: %{args.user | status: :active}}} end)

    update :user, from: :user
  end
end
