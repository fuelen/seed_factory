defmodule SeedFactoryTest do
  use ExUnit.Case, async: true
  use SeedFactory.Test, schema: SchemaExample

  test "rebind", context do
    {context, diff} =
      with_diff(context, fn ->
        context
        |> rebind([office: :office1, user: :user1, profile: :profile1], fn context ->
          context
          |> exec(:create_office, name: "My Office #1")
          |> exec(:create_user, name: "John Doe")
        end)
        |> rebind([office: :office2, user: :user2, profile: :profile2], fn context ->
          context
          |> exec(:create_office, name: "My Office #2")
          |> produce([:user])
        end)
      end)

    assert diff == %{
             added: [:office1, :office2, :org, :profile1, :profile2, :user1, :user2],
             deleted: [],
             updated: []
           }

    assert context.office1.name == "My Office #1"
    assert context.office2.name == "My Office #2"
    assert context.profile1.name == "John Doe"
  end

  test "rebind unknown entity", context do
    assert_raise ArgumentError, "Unknown entity :Office", fn ->
      rebind(context, [Office: :office1], fn context ->
        exec(context, :create_office, name: "My Office #1")
      end)
    end
  end

  describe "nested rebinding" do
    test "rebind + produce", context do
      {context, diff} =
        with_diff(context, fn ->
          rebind(context, [org: :org1], fn context ->
            context
            |> produce(office: :office11)
            |> produce(office: :office12)
          end)
          |> rebind([org: :org2], fn context ->
            context
            |> produce(office: :office21)
            |> produce(office: :office22)
          end)
        end)

      assert diff == %{
               added: [:office11, :office12, :office21, :office22, :org1, :org2],
               deleted: [],
               updated: []
             }

      assert context.office11.org_id == context.org1.id
      assert context.office12.org_id == context.org1.id

      assert context.office21.org_id == context.org2.id
      assert context.office22.org_id == context.org2.id
    end

    test "same binding", context do
      {_context, diff} =
        with_diff(context, fn ->
          rebind(context, [org: :org1], fn context ->
            rebind(context, [org: :org1], fn context ->
              produce(context, [:org])
            end)
          end)
        end)

      assert diff == %{added: [:org1], deleted: [], updated: []}
    end

    test "conflicting binding", context do
      assert_raise ArgumentError,
                   "Rebinding conflict. Cannot rebind `:org` to `:org2`. Current value `:org1`.",
                   fn ->
                     rebind(context, [org: :org1], fn context ->
                       rebind(context, [org: :org2], fn context ->
                         produce(context, [:org])
                       end)
                     end)
                   end
    end
  end

  test "resolver returns an error", context do
    assert_raise RuntimeError,
                 ~s|Unable to execute :resolve_with_error command: %{message: "OOPS", other_key: :data}|,
                 fn ->
                   exec(context, :resolve_with_error)
                 end
  end

  test "resolver raises an exception", context do
    assert_raise RuntimeError, "BOOM", fn ->
      exec(context, :raise_exception)
    end
  end

  test "updating a value in the context", context do
    {context, diff} = with_diff(context, fn -> produce(context, :user) end)
    assert context.user.status == :pending
    assert diff == %{added: [:office, :org, :profile, :user], deleted: [], updated: []}

    {context, diff} = with_diff(context, fn -> exec(context, :activate_user) end)
    assert diff == %{added: [], deleted: [], updated: [:user]}
    assert context.user.status == :active
  end

  test "updating a non-existing value", context do
    context = produce(context, :user)
    {user, context} = Map.pop!(context, :user)

    assert_raise ArgumentError,
                 "Cannot update entity :user while executing :activate_user: key :user doesn't exist in the context",
                 fn ->
                   exec(context, :activate_user, user: user)
                 end
  end

  test "deleting a value from the context", context do
    {context, diff} = with_diff(context, fn -> produce(context, [:draft_project]) end)
    assert diff == %{added: [:draft_project, :office, :org], deleted: [], updated: []}
    {_context, diff} = with_diff(context, fn -> produce(context, [:project]) end)

    assert diff == %{
             added: [:email, :profile, :project, :user],
             deleted: [:draft_project],
             updated: []
           }
  end

  test "deleting a non-existing value from the context", context do
    context = produce(context, [:draft_project])
    {draft_project, context} = Map.pop!(context, :draft_project)

    # Maybe, later deleting of non-existing values will be noop, but for the time being the operation is restricted
    assert_raise ArgumentError,
                 "Cannot delete entity :draft_project from the context while executing :publish_project: key :draft_project doesn't exist",
                 fn ->
                   exec(context, :publish_project, project: draft_project)
                 end
  end

  test "produce entity specified as an atom", context do
    {_context, diff} = with_diff(context, fn -> produce(context, :project) end)

    assert diff == %{
             added: [:email, :office, :org, :profile, :project, :user],
             deleted: [],
             updated: []
           }
  end

  test "produce unknown entity", context do
    assert_raise ArgumentError, "Unknown entity :unknown_entity", fn ->
      produce(context, :unknown_entity)
    end
  end

  test "produce entities specified as a simple list", context do
    {_context, diff} = with_diff(context, fn -> produce(context, [:draft_project, :user]) end)

    assert diff == %{
             added: [:draft_project, :office, :org, :profile, :user],
             deleted: [],
             updated: []
           }
  end

  test "produce entities with rebinding", context do
    {context, diff} =
      with_diff(context, fn ->
        context
        |> produce(office: :office1)
        |> produce(office: :office2)
      end)

    assert diff == %{added: [:office1, :office2, :org], deleted: [], updated: []}

    {_context, diff} =
      with_diff(context, fn ->
        context
        |> produce(office: :office3, project: :project1, email: :email1)
        |> produce(office: :office3, project: :project2, email: :email2)
      end)

    assert diff == %{
             added: [:email1, :email2, :office3, :profile, :project1, :project2, :user],
             deleted: [],
             updated: []
           }

    {_context, diff} =
      with_diff(context, fn ->
        context
        |> produce(office: [as: :office4])
      end)

    assert diff == %{added: [:office4], deleted: [], updated: []}
  end

  test "entity which can be produced by multiple commands uses 1st declared command by default",
       context do
    context
    |> produce(:email)
    |> assert_trait(:email, [:notification_about_published_project])
    |> assert_trait(:user, [:active, :normal, :free_plan])
    |> assert_trait(:project, [:not_expired])
  end

  describe "resolution when the an entity can be produced by multiple commands" do
    test "default command for :email entity is :publish_project", context do
      # one entity is specified
      {_context, diff} =
        with_diff(context, fn ->
          context
          |> produce(:email)
          |> assert_trait(:email, [:notification_about_published_project])
        end)

      assert diff == %{
               added: [:email, :office, :org, :profile, :project, :user],
               deleted: [],
               updated: []
             }

      # when multiple entities are specified
      {_context, diff} =
        with_diff(context, fn ->
          context
          |> produce([:email, :org])
          |> assert_trait(:email, [:notification_about_published_project])
          |> assert_trait(:user, [:active, :normal, :free_plan])
        end)

      assert diff == %{
               added: [:email, :office, :org, :profile, :project, :user],
               deleted: [],
               updated: []
             }
    end

    test "switch to another command for producing :email if there is an additional requirement",
         context do
      # all instructions for producing email are on the top level (user: [:suspended] produces an email)

      # `:email` is specified without traits
      {_context, diff} =
        with_diff(context, fn ->
          context
          |> produce([:email, user: [:suspended]])
          |> assert_trait(:email, [:notification_about_suspended_user])
        end)

      assert diff == %{added: [:email, :office, :org, :profile, :user], deleted: [], updated: []}

      # `:email` specified with traits
      {_context, diff} =
        with_diff(context, fn ->
          context
          |> produce(email: [:delivered], user: [:suspended])
          |> assert_trait(:email, [:delivered, :notification_about_suspended_user])
        end)

      assert diff == %{
               added: [:email, :office, :org, :profile, :user],
               deleted: [],
               updated: []
             }

      # only one of the instructions about producing email is on the top level
      # (profile: [:anonymized] depends on a command that produces an email)

      # `email` with traits

      {_context, diff} =
        with_diff(context, fn ->
          context
          |> produce(email: [:delivered], profile: [:anonymized])
          |> assert_trait(:email, [:delivered, :notification_about_suspended_user])
        end)

      assert diff == %{
               added: [:email, :office, :org, :profile, :user],
               deleted: [],
               updated: []
             }

      # `email` without traits

      {_context, diff} =
        with_diff(context, fn ->
          context
          |> produce([:email, profile: [:anonymized]])
          |> assert_trait(:email, [:notification_about_suspended_user])
        end)

      assert diff == %{
               added: [:email, :office, :org, :profile, :user],
               deleted: [],
               updated: []
             }

      # only one of the instructions about producing email is on the top level
      # (files_removal_task: [] is 1 level deeper than profile: [:anonymized] which was used in previous assertions)

      # `email` without traits

      {_context, diff} =
        with_diff(context, fn ->
          context
          |> produce(email: [], files_removal_task: [])
          |> assert_trait(:email, [:notification_about_suspended_user])
        end)

      assert diff == %{
               added: [:email, :files_removal_task, :office, :org, :profile, :user],
               deleted: [],
               updated: []
             }

      # `email` with traits
      {_context, diff} =
        with_diff(context, fn ->
          context
          |> produce(email: [:delivered], files_removal_task: [])
          |> assert_trait(:email, [:delivered, :notification_about_suspended_user])
        end)

      assert diff == %{
               added: [:email, :files_removal_task, :office, :org, :profile, :user],
               deleted: [],
               updated: []
             }

      # two conflict groups: for draft_project and for email

      {_context, diff} =
        with_diff(context, fn ->
          context
          |> produce(draft_project: [], email: [])
          |> assert_trait(:email, [:notification_about_published_project])
          |> assert_trait(:project, [:not_expired])
        end)

      assert diff == %{
               added: [:email, :office, :org, :profile, :project, :user],
               deleted: [],
               updated: []
             }

      {_context, diff} =
        with_diff(context, fn ->
          context
          |> produce([:draft_project, email: [:delivered]])
          |> assert_trait(:email, [:delivered, :notification_about_published_project])
        end)

      assert diff == %{
               added: [:email, :office, :org, :profile, :project, :user],
               deleted: [],
               updated: []
             }
    end

    test "execute command that deletes entity only when it is no longer needed", context do
      # when we have a graph where add_proposal_v1 requires draft_project and publish_project
      # requires draft_project as well, but publish_project deletes it from the context, so publish_project MUST
      # be executed before add_proposal_v1.
      #                            ┌──►add_proposal_v1─┐
      #                            │                   │
      #                            │                   │
      # ────►create_draft_project──┤                   ├───►nil
      #                            │                   │
      #                            │                   │
      #                            └──►publish_project─┘
      # For this reason we add additional relations, so the graph above becomes
      #                            ┌──►add_proposal_v1──┬───────────────┐
      #                            │                    │               │
      #                            │                    │               │
      # ────►create_draft_project──┤                    │               ├─►nil
      #                            │                    │               │
      #                            │                    ▼               │
      #                            └───────────────────►publish_project─┘
      {_context, diff} =
        with_diff(context, fn ->
          context
          |> produce(proposal: [], project: [])
          |> assert_trait(:project, [:not_expired])
        end)

      assert diff == %{
               added: [:email, :office, :org, :profile, :project, :proposal, :user],
               deleted: [],
               updated: []
             }
    end

    test "same traits can be applied by multiple commands", context do
      context
      |> produce(user: [:normal, :pending_skipped])
      |> assert_trait(:user, [:active, :normal, :free_plan, :pending_skipped])

      context
      |> produce(user: [:pending_skipped, :normal])
      |> assert_trait(:user, [:active, :normal, :free_plan, :pending_skipped])

      context
      |> produce([:profile, user: [:pending_skipped]])
      |> assert_trait(:user, [:active, :normal, :free_plan, :pending_skipped])

      context
      |> produce([:profile, user: [:pending_skipped, :suspended]])
      |> assert_trait(:user, [:suspended, :normal, :free_plan, :pending_skipped])

      context
      |> exec(:create_active_user)
      |> assert_trait(:user, [:active, :normal, :free_plan, :pending_skipped])
      |> produce(user: [:suspended])
      |> assert_trait(:user, [:suspended, :normal, :free_plan, :pending_skipped])
      |> produce(user: [:suspended, :normal, :free_plan])
      |> assert_trait(:user, [:suspended, :normal, :free_plan, :pending_skipped])
    end
  end

  test "produce entity with traits when it was already created without traits", context do
    assert_raise ArgumentError,
                 """
                 Traits to previously executed command :create_user do not match:
                   previously applied traits: []
                   specified trait: :contacts_confirmed
                 """,
                 fn ->
                   context
                   |> produce(:profile)
                   |> produce(profile: [:contacts_confirmed])
                 end
  end

  test "entity can be produced by non-default command using traits",
       context do
    context =
      context
      |> produce(email: [:notification_about_suspended_user])
      |> assert_trait(:user, [:suspended, :normal, :free_plan])

    refute Map.has_key?(context, :project)
  end

  test "exec command with generators only", context do
    {context, diff} = with_diff(context, fn -> exec(context, :create_org) end)
    assert diff == %{added: [:org], deleted: [], updated: []}
    assert is_binary(context.org.name)
    assert is_binary(context.org.address.country)
    assert is_binary(context.org.address.city)
  end

  test "exec command with custom params", context do
    {context, diff} =
      with_diff(context, fn ->
        exec(context, :create_org, name: "QWERTY", address: [country: "Ukraine"])
      end)

    assert diff == %{added: [:org], deleted: [], updated: []}
    assert context.org.name == "QWERTY"
    assert context.org.address.country == "Ukraine"
    assert is_binary(context.org.address.city)
  end

  test "exec command with automatically created dependent entity", context do
    {_context, diff} = with_diff(context, fn -> exec(context, :create_office) end)
    assert diff == %{added: [:office, :org], deleted: [], updated: []}
  end

  test "exec command with map option - applies map function to entity", context do
    context = exec(context, :create_user)
    assert context.user.office_id == context.office.id
  end

  test "exec command with map option - doesn't apply map function to explicitly passed parameter",
       context do
    context = exec(context, :create_user, office_id: "MY_OFFICE_ID")
    assert context.user.office_id == "MY_OFFICE_ID"
  end

  test "exec command with manually specified dependent entity", context do
    context =
      context
      |> produce(org: :org1)
      |> produce(org: :org2)

    {context, diff} =
      with_diff(context, fn -> exec(context, :create_office, org: context.org2) end)

    assert context.office.org_id == context.org2.id
    assert diff == %{added: [:office], deleted: [], updated: []}
  end

  test "exec unknown command", context do
    assert_raise ArgumentError,
                 "Unknown command :unknown_command",
                 fn ->
                   exec(context, :unknown_command)
                 end
  end

  test "double execution of the same command", context do
    assert_raise ArgumentError,
                 "Cannot put entity :org to the context while executing :create_org: key :org already exists",
                 fn ->
                   context
                   |> exec(:create_org)
                   |> exec(:create_org)
                 end
  end

  test "redundant parameters", context do
    assert_raise ArgumentError,
                 "Input doesn't match defined params. Redundant keys found: [:unknown_param1, :unknown_param2]",
                 fn ->
                   exec(context, :create_org,
                     unknown_param1: "heey",
                     name: "QWERTY",
                     unknown_param2: "heey2"
                   )
                 end
  end

  describe "traits" do
    test "replacing traits when `from` in schema is specified as a list", context do
      context
      |> produce(task: [:completed])
      |> assert_trait(:task, [:completed])

      context
      |> produce(task: [:todo])
      |> assert_trait(:task, [:todo])
      |> produce(task: [:completed])
      |> assert_trait(:task, [:completed])

      context
      |> produce(task: [:in_progress])
      |> assert_trait(:task, [:in_progress])
      |> produce(task: [:completed])
      |> assert_trait(:task, [:completed])
    end

    test "automatic detection of traits from params", context do
      context
      |> exec(:create_user, role: :admin)
      |> assert_trait(:user, [:admin, :pending, :unknown_plan])

      context
      |> produce(:user)
      |> assert_trait(:user, [:normal, :pending, :unknown_plan])
      |> exec(:activate_user)
      |> assert_trait(:user, [:normal, :active, :free_plan])
    end

    test "`produce` with single trait", context do
      context
      |> produce(user: [:suspended])
      |> assert_trait(:user, [:normal, :suspended, :free_plan])
    end

    test "`exec` which requires entities with traits", context do
      context
      |> exec(:suspend_user)
      |> assert_trait(:user, [:normal, :suspended, :free_plan])

      context
      |> produce(user: [:admin])
      |> exec(:suspend_user)
      |> assert_trait(:user, [:admin, :suspended, :free_plan])
    end

    test "`delete` instruction clears traits from meta", context do
      context =
        context
        |> produce(:user)
        |> assert_trait(:user, [:normal, :pending, :unknown_plan])
        |> exec(:delete_user)

      refute Map.has_key?(context.__seed_factory_meta__.current_traits, :user)
    end

    test "`produce` with multiple traits from different commands",
         context do
      context
      |> produce(user: [:suspended, :paid_plan, :admin])
      |> assert_trait(:user, [:suspended, :paid_plan, :admin])
    end

    test "update entity with new traits", context do
      context
      |> produce(user: [:admin])
      |> assert_trait(:user, [:admin, :pending, :unknown_plan])
      |> produce(user: [:paid_plan])
      |> assert_trait(:user, [:admin, :active, :paid_plan])
      |> produce(user: [:suspended])
      |> assert_trait(:user, [:admin, :suspended, :paid_plan])
    end

    test "`produce` entity with the same traits multiple times", context do
      context
      |> produce(user: [:admin])
      |> assert_trait(:user, [:admin, :pending, :unknown_plan])
      |> produce(user: [:paid_plan])
      |> assert_trait(:user, [:admin, :active, :paid_plan])
      |> produce(user: [:paid_plan])
      |> assert_trait(:user, [:admin, :active, :paid_plan])
    end

    test "same command produces entities with traits", context do
      context
      |> produce([:user, :profile])
      |> assert_trait(:user, [:normal, :pending, :unknown_plan])
      |> assert_trait(:profile, [])

      context
      |> produce(virtual_file: [:public], user: [:admin, :active], profile: [:contacts_confirmed])
      |> assert_trait(:virtual_file, [:public])
      |> assert_trait(:user, [:admin, :active, :free_plan])
      |> assert_trait(:profile, [:contacts_confirmed])

      context
      |> produce(user: [:admin], profile: [:contacts_confirmed])
      |> assert_trait(:user, [:admin, :pending, :unknown_plan])
      |> assert_trait(:profile, [:contacts_confirmed])
      |> produce(virtual_file: [:public], user: [:active])
      |> assert_trait(:virtual_file, [:public])
      |> assert_trait(:user, [:admin, :active, :free_plan])
    end

    test "different conflict groups of the same command merge into 1 which is smaller", context do
      {_context, diff} =
        with_diff(context, fn ->
          context
          |> produce([:draft_project, :proposal, :imported_item_log])
          |> assert_trait(:draft_project, [:third_party])
        end)

      assert diff == %{
               added: [:draft_project, :imported_item_log, :office, :org, :proposal],
               deleted: [],
               updated: []
             }

      {_context, diff} =
        with_diff(context, fn ->
          context
          |> produce([:proposal, :imported_item_log])
          |> assert_trait(:draft_project, [:third_party])
        end)

      assert diff == %{
               added: [:draft_project, :imported_item_log, :office, :org, :proposal],
               deleted: [],
               updated: []
             }

      {_context, diff} =
        with_diff(context, fn ->
          context
          |> produce([:imported_item_log, :proposal])
          |> assert_trait(:draft_project, [:third_party])
        end)

      assert diff == %{
               added: [:draft_project, :imported_item_log, :office, :org, :proposal],
               deleted: [],
               updated: []
             }

      context
      |> produce([:approved_candidate, :candidate_profile])
      |> assert_trait(:approved_candidate, [:approved_using_approval_process])
    end

    test "specify traits which conflict with previously applied traits", context do
      assert_raise ArgumentError,
                   """
                   Traits to previously executed command :create_user do not match:
                     previously applied traits: [:unknown_plan, :admin, :pending]
                     specified trait: :normal
                   """,
                   fn ->
                     context
                     |> produce(user: [:admin])
                     |> assert_trait(:user, [:admin, :pending, :unknown_plan])
                     |> produce(user: [:normal])
                   end

      assert_raise ArgumentError,
                   """
                   Traits to previously executed command :publish_project do not match:
                     previously applied traits: [:expired]
                     trait required by :create_virtual_file command: :not_expired
                   """,
                   fn ->
                     context
                     |> produce(project: [:expired], user: [:admin])
                     |> produce(:virtual_file)
                   end
    end

    test "commands that remove entities should be executed at the end", context do
      # it is important, that :publish_project command is executed before :suspend_user, so we have expected error
      # and not "Cannot put entity :email to the context while executing :publish_project: key :email already exists"
      assert_raise ArgumentError,
                   "Cannot put entity :email to the context while executing :suspend_user: key :email already exists",
                   fn ->
                     produce(context, [:project, user: [:suspended]])
                   end
    end

    test "specify traits which conflict with requirements of other entities", context do
      # virtual_file requires :admin trait, which requires creation of the user with role param
      assert_raise ArgumentError,
                   """
                   Cannot merge arguments generated by traits for command :create_user.
                     Path: [:role]
                     Value 1: :normal
                     Value 2: :admin
                   """,
                   fn ->
                     produce(context, [:virtual_file, user: [:normal]])
                   end

      # :project requires active user.
      # in order to :activate user, we execute :activate_user command to move user from :pending to :active status
      assert_raise ArgumentError,
                   """
                   Cannot apply traits [:active] to :user as a requirement for :publish_project command.
                   The entity was requested with the following traits: [:pending, :admin].
                   """,
                   fn ->
                     produce(context, [:project, user: [:pending, :admin]])
                   end

      assert_raise ArgumentError,
                   """
                   Cannot apply traits [:pending] to :user1 because they were removed by the command :activate_user.
                   Current traits: [:normal, :free_plan, :active].
                   """,
                   fn ->
                     context
                     |> produce([:project, user: :user1])
                     |> produce(user: [:pending, as: :user1])
                   end

      assert_raise ArgumentError,
                   """
                   Cannot apply traits [:pending] to :user.
                   There is no path from traits [:active].
                   Current traits: [:free_plan, :normal, :pending_skipped, :active].
                   """,
                   fn ->
                     context
                     |> exec(:create_active_user)
                     |> produce(user: [:pending])
                   end
    end

    test "traits defined with generate_args and args_match options", context do
      today = Date.utc_today()

      context
      |> exec(:publish_project, expiry_date: Date.add(today, 10), start_date: Date.add(today, 2))
      |> assert_trait(:project, [:not_expired])

      context
      |> exec(:publish_project,
        expiry_date: Date.add(today, -1),
        start_date: Date.add(today, -22)
      )
      |> assert_trait(:project, [:expired])

      context
      |> produce(:project)
      |> assert_trait(:project, [:not_expired])

      context
      |> produce(project: [:not_expired])
      |> assert_trait(:project, [:not_expired])

      context
      |> produce(project: [:expired])
      |> assert_trait(:project, [:expired])

      context
      |> produce(project: [:expired, :archived])
      |> assert_trait(:project, [:expired, :archived])
    end

    test "entity doesn't have traits", context do
      assert_raise ArgumentError, "Entity :org doesn't have traits", fn ->
        produce(context, org: [:something])
      end
    end

    test "unknown traits", context do
      assert_raise ArgumentError, "Entity :user doesn't have trait :something", fn ->
        produce(context, user: [:something])
      end
    end

    test "multiple traits which use the same parameter of the entity", context do
      # same entity with conflicting traits
      assert_raise ArgumentError,
                   """
                   Cannot merge arguments generated by traits for command :create_user.
                     Path: [:role]
                     Value 1: :normal
                     Value 2: :admin
                   """,
                   fn -> produce(context, user: [:normal, :admin]) end

      # same entity with conflicting traits, deep map comparison
      assert_raise ArgumentError,
                   """
                   Cannot merge arguments generated by traits for command :activate_user.
                     Path: [:finances, :plan]
                     Value 1: :paid
                     Value 2: :free
                   """,
                   fn -> produce(context, user: [:paid_plan, :free_plan]) end

      assert_raise ArgumentError,
                   ~r"""
                   Cannot apply trait :not_expired of entity :project to generated args for command :publish_project.
                   Generated args: %\{expiry_date:\ ~D\[.+\],\ start_date:\ ~D\[.+\]\}
                   """,
                   fn -> produce(context, [:virtual_file, project: [:expired]]) end
    end

    test "accumulate traits using update instruction", context do
      # duplicating traits is not something that we really need,
      # but this test is present just to track the behaviour

      context =
        context
        |> produce(virtual_file: :virtual_file1)
        |> produce(virtual_file: :virtual_file2)
        |> assert_trait(:project, [:not_expired, :with_virtual_file, :with_virtual_file])

      context
      |> rebind([virtual_file: :virtual_file1], fn context ->
        context
        |> produce(project: [:with_virtual_file])
      end)
      |> assert_trait(:project, [:not_expired, :with_virtual_file, :with_virtual_file])
    end
  end

  test "pre_exec", context do
    {_context, diff} =
      with_diff(context, fn ->
        pre_exec(context, :create_user)
      end)

    assert diff == %{added: [:office, :org], deleted: [], updated: []}

    {_context, diff} =
      with_diff(context, fn ->
        pre_exec(context, :create_user, office_id: :fake_office_id)
      end)

    assert diff == %{added: [], deleted: [], updated: []}

    {_context, diff} =
      with_diff(context, fn ->
        pre_exec(context, :activate_user)
      end)

    assert diff == %{added: [:office, :org, :profile, :user], deleted: [], updated: []}
  end

  test "pre_produce", context do
    {_context, diff} =
      with_diff(context, fn ->
        pre_produce(context, :office)
      end)

    assert diff == %{added: [:org], deleted: [], updated: []}

    {_context, diff} =
      with_diff(context, fn ->
        pre_produce(context, user: [:active])
      end)

    assert diff == %{added: [:office, :org], deleted: [], updated: []}

    {_context, diff} =
      with_diff(context, fn ->
        pre_produce(context, [:office, user: [:active]])
      end)

    assert diff == %{added: [:org], deleted: [], updated: []}

    {_context, diff} =
      with_diff(context, fn ->
        pre_produce(context, [:office, :virtual_file])
      end)

    assert diff == %{added: [:org], deleted: [], updated: []}
  end

  describe "manually put entities to context" do
    test "entity that can have traits", context do
      context = Map.put(context, :user, %SchemaExample.User{id: "user-id-1"})

      assert_raise(
        RuntimeError,
        """
        Can't find trail for :user entity.
        Please don't put entities that can have traits manually in the context.
        """,
        fn -> exec(context, :publish_project) end
      )
    end

    test "entity that cannot have traits", context do
      context = Map.put(context, :org, %SchemaExample.Org{id: "org-id-1"})

      {_context, diff} =
        with_diff(context, fn ->
          exec(context, :create_office)
        end)

      assert diff == %{added: [:office], deleted: [], updated: []}
    end
  end

  defp assert_trait(context, binding_name, expected_traits) when is_list(expected_traits) do
    assert Map.has_key?(context, binding_name),
           "No produced entity bound to #{inspect(binding_name)}"

    current_traits =
      Map.get(context.__seed_factory_meta__.current_traits, binding_name) ||
        raise "No tracked traits for #{inspect(binding_name)}"

    assert Enum.sort(expected_traits) == Enum.sort(current_traits)

    context
  end

  def with_diff(context, callback) do
    initial_context_keys = Map.keys(context) -- [:__seed_factory_meta__]
    new_context = callback.()
    new_context_keys = Map.keys(new_context) -- [:__seed_factory_meta__]

    added = new_context_keys -- initial_context_keys
    deleted = initial_context_keys -- new_context_keys

    updated =
      Enum.reject(new_context_keys -- added, fn element ->
        context[element] == new_context[element]
      end)

    {new_context,
     %{added: Enum.sort(added), deleted: Enum.sort(deleted), updated: Enum.sort(updated)}}
  end
end
