defmodule SchemaExample do
  use SeedFactory.Schema

  defmodule Org, do: defstruct([:id, :name, :address])
  defmodule Office, do: defstruct([:id, :name, :org_id])
  defmodule User, do: defstruct([:id, :name, :office_id, :status, :role, :plan])
  defmodule Profile, do: defstruct([:id, :user_id, :contacts_confirmed?])

  defmodule Project,
    do: defstruct([:id, :name, :office_id, :draft?, :published_by_id, :virtual_files])

  defmodule VirtualFile, do: defstruct([:id, :content, :project_id, :author_id, :privacy])

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
    param :name, generate: &random_string/0

    param :address do
      param :city, generate: &random_string/0
      param :country, generate: &random_string/0
    end

    resolve(fn args ->
      org = %Org{name: args.name, address: args.address, id: gen_id()}
      {:ok, %{org: org}}
    end)

    produce :org, from: :org
  end

  command :create_office do
    param :name, generate: &random_string/0
    param :org, entity: :org

    resolve(fn args ->
      office = %Office{name: args.name, org_id: args.org.id, id: gen_id()}
      {:ok, %{office: office}}
    end)

    produce :office, from: :office
  end

  command :create_draft_project do
    param :name, generate: &random_string/0
    param :office, entity: :office

    resolve(fn args ->
      project = %Project{name: args.name, draft?: true, office_id: args.office.id, id: gen_id()}
      {:ok, %{project: project}}
    end)

    produce :draft_project, from: :project
  end

  command :publish_project do
    param :project, entity: :draft_project
    param :published_by, entity: :user, with_traits: [:active]

    resolve(fn args ->
      {:ok, %{project: %{args.project | draft?: false, published_by_id: args.published_by.id}}}
    end)

    produce :project, from: :project
    delete :draft_project
  end

  command :create_user do
    param :name, generate: &random_string/0
    param :role, value: :normal
    param :contacts_confirmed?, value: false
    param :office_id, entity: :office, map: &get_id/1

    resolve(fn args ->
      user = %User{
        name: args.name,
        office_id: args.office_id,
        id: gen_id(),
        status: :pending,
        role: args.role,
        plan: :unknown
      }

      profile = %Profile{
        id: gen_id(),
        user_id: user.id,
        contacts_confirmed?: args.contacts_confirmed?
      }

      {:ok, %{user: user, profile: profile}}
    end)

    produce :user, from: :user
    produce :profile, from: :profile
  end

  command :activate_user do
    param :user, entity: :user, with_traits: [:pending]

    param :finances do
      param :plan, value: :trial
    end

    resolve(fn args ->
      {:ok, %{user: %{args.user | status: :active, plan: args.finances.plan}}}
    end)

    update :user, from: :user
  end

  command :suspend_user do
    param :user, entity: :user, with_traits: [:active]

    resolve(fn args -> {:ok, %{user: %{args.user | status: :suspended}}} end)

    update :user, from: :user
  end

  command :delete_user do
    param :user, entity: :user, with_traits: [:active]

    resolve(fn _args -> {:ok, %{}} end)

    delete :user
  end

  command :create_virtual_file do
    param :content, generate: &random_string/0
    param :privacy, value: :private
    param :project, entity: :project
    param :author, entity: :user, with_traits: [:active, :admin]

    resolve(fn args ->
      file = %VirtualFile{
        content: args.content,
        author_id: args.author.id,
        project_id: args.project.id,
        privacy: args.privacy,
        id: gen_id()
      }

      project = %{args.project | virtual_files: [file | args.project.virtual_files]}

      {:ok, %{file: file, project: project}}
    end)

    produce :virtual_file, from: :file
    update :project, from: :project
  end

  trait :pending, :user do
    exec :create_user
  end

  trait :active, :user do
    from :pending
    exec :activate_user
  end

  trait :suspended, :user do
    from :active
    exec :suspend_user
  end

  trait :normal, :user do
    exec :create_user, args_pattern: %{role: :normal}
  end

  trait :admin, :user do
    exec :create_user, args_pattern: %{role: :admin}
  end

  trait :unknown_plan, :user do
    exec :create_user
  end

  trait :contacts_unconfirmed, :profile do
    exec :create_user, args_pattern: %{contacts_confirmed?: false}
  end

  trait :contacts_confirmed, :profile do
    exec :create_user, args_pattern: %{contacts_confirmed?: true}
  end

  trait :public, :virtual_file do
    exec :create_virtual_file, args_pattern: %{privacy: :public}
  end

  trait :private, :virtual_file do
    exec :create_virtual_file, args_pattern: %{privacy: :private}
  end

  trait :free_plan, :user do
    from :unknown_plan
    exec :activate_user, args_pattern: %{finances: %{plan: :free}}
  end

  trait :paid_plan, :user do
    from :unknown_plan
    exec :activate_user, args_pattern: %{finances: %{plan: :paid}}
  end

  trait :with_virtual_file, :project do
    exec :create_virtual_file
  end
end
