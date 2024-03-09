defmodule SchemaExample do
  use SeedFactory.Schema

  defmodule Org, do: defstruct([:id, :name, :address])
  defmodule Office, do: defstruct([:id, :name, :org_id])
  defmodule User, do: defstruct([:id, :office_id, :status, :role, :plan, :profile_id])
  defmodule Profile, do: defstruct([:id, :name, :contacts_confirmed?])
  defmodule Email, do: defstruct([:content, delivered?: false])
  defmodule Proposal, do: defstruct([:version])
  defmodule FilesRemovalTask, do: defstruct([:id, :profile_id])

  defmodule Project do
    defstruct [
      :id,
      :name,
      :office_id,
      :draft?,
      :source,
      :published_by_id,
      :virtual_files,
      :expiry_date,
      :start_date
    ]
  end

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

    update :user
  end

  command :resolve_with_error do
    resolve(fn _args ->
      {:error, %{message: "OOPS", other_key: :data}}
    end)

    update :user
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

    produce :org
  end

  command :create_office do
    param :name, generate: &random_string/0
    param :org, entity: :org

    resolve(fn args ->
      office = %Office{name: args.name, org_id: args.org.id, id: gen_id()}
      {:ok, %{office: office}}
    end)

    produce :office
  end

  command :create_draft_project do
    param :name, generate: &random_string/0
    param :office, entity: :office

    resolve(fn args ->
      project = %Project{
        name: args.name,
        draft?: true,
        office_id: args.office.id,
        id: gen_id(),
        source: :internal
      }

      {:ok, %{project: project}}
    end)

    produce :draft_project, from: :project
  end

  command :import_draft_project_from_third_party_service do
    param :name, generate: &random_string/0
    param :office, entity: :office

    resolve(fn args ->
      project = %Project{
        name: args.name,
        draft?: true,
        office_id: args.office.id,
        id: gen_id(),
        source: :third_party
      }

      {:ok, %{project: project, imported_item_log: "draft from third-party service"}}
    end)

    produce :draft_project, from: :project
    produce :imported_item_log
  end

  command :import_draft_project_from_ftp_server do
    param :name, generate: &random_string/0
    param :office, entity: :office

    resolve(fn args ->
      project = %Project{
        name: args.name,
        draft?: true,
        office_id: args.office.id,
        id: gen_id(),
        source: :ftp
      }

      {:ok, %{project: project, imported_item_log: "draft from FTP-server"}}
    end)

    produce :draft_project, from: :project
    produce :imported_item_log
  end

  command :publish_project do
    param :project, entity: :draft_project
    param :published_by, entity: :user, with_traits: [:active]
    param :start_date, generate: fn -> Date.utc_today() end
    param :expiry_date, generate: fn -> Date.utc_today() |> Date.add(21) end

    resolve(fn args ->
      {:ok,
       %{
         project: %{
           args.project
           | draft?: false,
             published_by_id: args.published_by.id,
             start_date: args.start_date,
             expiry_date: args.expiry_date
         },
         email: %Email{content: "Project has been published"}
       }}
    end)

    produce :project
    produce :email
    delete :draft_project
  end

  command :deliver_email do
    param :email, entity: :email

    resolve(fn args ->
      {:ok, %{email: %{args.email | delivered?: true}}}
    end)

    update :email
  end

  command :create_user do
    param :name, generate: &random_string/0
    param :role, value: :normal
    param :contacts_confirmed?, value: false
    param :office_id, entity: :office, map: &get_id/1

    resolve(fn args ->
      profile = %Profile{
        name: args.name,
        id: gen_id(),
        contacts_confirmed?: args.contacts_confirmed?
      }

      user = %User{
        office_id: args.office_id,
        profile_id: profile.id,
        id: gen_id(),
        status: :pending,
        role: args.role,
        plan: :unknown
      }

      {:ok, %{user: user, profile: profile}}
    end)

    produce :user
    produce :profile
  end

  command :activate_user do
    param :user, entity: :user, with_traits: [:pending]

    param :finances do
      param :plan, value: :trial
    end

    resolve(fn args ->
      {:ok, %{user: %{args.user | status: :active, plan: args.finances.plan}}}
    end)

    update :user
  end

  command :suspend_user do
    param :user, entity: :user, with_traits: [:active]

    resolve(fn args ->
      {:ok,
       %{
         user: %{args.user | status: :suspended},
         email: %Email{content: "User has been suspended"}
       }}
    end)

    update :user
    produce :email
  end

  command :anonymize_profile_of_suspended_user do
    param :user, entity: :user, with_traits: [:suspended]
    param :profile, entity: :profile

    resolve(fn args ->
      {:ok, %{profile: %{args.profile | name: "Anonymized"}}}
    end)

    update :profile
  end

  command :schedule_files_removal do
    param :profile, entity: :profile, with_traits: [:anonymized]

    resolve(fn args ->
      {:ok, %{task: %FilesRemovalTask{id: gen_id(), profile_id: args.profile.id}}}
    end)

    produce :files_removal_task, from: :task
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
    update :project
  end

  trait :delivered, :email do
    exec :deliver_email
  end

  trait :notification_about_published_project, :email do
    exec :publish_project
  end

  trait :notification_about_suspended_user, :email do
    exec :suspend_user
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

  trait :anonymized, :profile do
    exec :anonymize_profile_of_suspended_user
  end

  trait :with_virtual_file, :project do
    exec :create_virtual_file
  end

  trait :third_party, :draft_project do
    exec :import_draft_project_from_third_party_service
  end

  trait :ftp_server, :draft_project do
    exec :import_draft_project_from_ftp_server
  end

  trait :not_expired, :project do
    exec :publish_project do
      args_match(fn args -> Date.compare(Date.utc_today(), args.expiry_date) in [:lt, :eq] end)

      generate_args(fn ->
        today = Date.utc_today()
        %{start_date: today, expiry_date: Date.add(today, 21)}
      end)
    end
  end

  trait :expired, :project do
    exec :publish_project do
      args_match(fn args -> Date.compare(Date.utc_today(), args.expiry_date) == :gt end)

      generate_args(fn ->
        today = Date.utc_today()
        %{start_date: Date.add(today, -22), expiry_date: Date.add(today, -1)}
      end)
    end
  end

  command :add_proposal_v1 do
    param :draft_project, entity: :draft_project

    resolve(fn args ->
      {:ok, %{proposal: %Proposal{version: 1}}}
    end)

    produce :proposal
  end

  command :add_proposal_v2 do
    param :draft_project, entity: :draft_project

    resolve(fn args ->
      {:ok, %{proposal: %Proposal{version: 2}}}
    end)

    produce :proposal
  end

  command :start_approval_process do
    resolve(fn _ ->
      {:ok, %{approval_process: :process, candidate_profile: :candidate_profile}}
    end)

    produce :approval_process
    produce :candidate_profile
  end

  command :approve_candidate do
    param :approval_process, entity: :approval_process

    resolve(fn _ ->
      {:ok, %{approval_process: :finished_process, approved_candidate: :approved_candidate}}
    end)

    update :approval_process
    produce :approved_candidate
  end

  command :create_approved_candidate do
    resolve(fn _ -> {:ok, %{candidate_profile: :candidate_profile}} end)
    produce :candidate_profile
    produce :approved_candidate
  end

  trait :approved_immediatelly, :approved_candidate do
    exec :create_approved_candidate
  end

  trait :approved_using_approval_process, :approved_candidate do
    exec :approve_candidate
  end
end
