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
    assert context.user1.name == "John Doe"
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
                 ~s|Unable to execue :resolve_with_error command: %{message: "OOPS", other_key: :data}|,
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
                 "Cannot update entity :user: key :user doesn't exist in the context",
                 fn ->
                   exec(context, :activate_user, user: user)
                 end
  end

  test "deleting a value from the context", context do
    {context, diff} = with_diff(context, fn -> produce(context, [:draft_project]) end)
    assert diff == %{added: [:draft_project, :office, :org], deleted: [], updated: []}
    {_context, diff} = with_diff(context, fn -> produce(context, [:project]) end)
    assert diff == %{added: [:profile, :project, :user], deleted: [:draft_project], updated: []}
  end

  test "deleting a non-existing value from the context", context do
    context = produce(context, [:draft_project])
    {draft_project, context} = Map.pop!(context, :draft_project)

    # Maybe, later deleting of non-existing values will be noop, but for the time being the operation is restricted
    assert_raise RuntimeError,
                 "Cannot delete entity :draft_project from the context: key :draft_project doesn't exist",
                 fn ->
                   exec(context, :publish_project, project: draft_project)
                 end
  end

  test "produce entity specified as an atom", context do
    {_context, diff} = with_diff(context, fn -> produce(context, :project) end)
    assert diff == %{added: [:office, :org, :profile, :project, :user], deleted: [], updated: []}
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
        |> produce(office: :office3, project: :project1)
        |> produce(office: :office3, project: :project2)
      end)

    assert diff == %{
             added: [:office3, :profile, :project1, :project2, :user],
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
                 "Cannot put entity :org to the context: key :org already exists",
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
    test "automatic detection of traits from params", context do
      context
      |> exec(:create_user, role: :admin)
      |> assert_trait(:user, [:admin, :pending, :unknown_plan])

      context
      |> produce(:user)
      |> assert_trait(:user, [:normal, :pending, :unknown_plan])
      |> exec(:activate_user)
      |> assert_trait(:user, [:normal, :active, :unknown_plan])
    end

    test "`produce` with single trait", context do
      context
      |> produce(user: [:suspended])
      |> assert_trait(:user, [:normal, :suspended, :unknown_plan])
    end

    test "`exec` which requires entities with traits", context do
      context
      |> exec(:suspend_user)
      |> assert_trait(:user, [:normal, :suspended, :unknown_plan])

      context
      |> produce(user: [:admin])
      |> exec(:suspend_user)
      |> assert_trait(:user, [:admin, :suspended, :unknown_plan])
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
      |> assert_trait(:profile, [:contacts_unconfirmed])

      context
      |> produce(virtual_file: [:public], user: [:admin, :active], profile: [:contacts_confirmed])
      |> assert_trait(:virtual_file, [:public])
      |> assert_trait(:user, [:admin, :active, :unknown_plan])
      |> assert_trait(:profile, [:contacts_confirmed])

      context
      |> produce(user: [:admin], profile: [:contacts_confirmed])
      |> assert_trait(:user, [:admin, :pending, :unknown_plan])
      |> assert_trait(:profile, [:contacts_confirmed])
      |> produce(virtual_file: [:public], user: [:active])
      |> assert_trait(:virtual_file, [:public])
      |> assert_trait(:user, [:admin, :active, :unknown_plan])
    end

    test "specify traits which conflict with previously applied traits", context do
      assert_raise ArgumentError,
                   """
                   Args to previously executed command :create_user do not match:
                     args from previously applied traits: %{role: :admin}
                     args for specified traits: %{role: :normal}
                   """,
                   fn ->
                     context
                     |> produce(user: [:admin])
                     |> assert_trait(:user, [:admin, :pending, :unknown_plan])
                     |> produce(user: [:normal])
                   end
    end

    test "specify traits which conflict with requirements of other entities", context do
      # virtual_file requires :admin trait, which requires creation of the user with role param
      assert_raise ArgumentError,
                   """
                   Cannot merge arguments generated by traits.
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
                   Cannot apply trait :active to entity :user.
                   The entity was requested with the following traits: [:pending]
                   """,
                   fn ->
                     produce(context, [:project, user: [:pending]])
                   end

      assert_raise ArgumentError,
                   """
                   Cannot apply traits [:pending] to entity :user.
                   The entity already exists with traits that depend on requested ones.
                   """,
                   fn ->
                     context
                     |> produce(:project)
                     |> produce(user: [:pending])
                   end
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
                   Cannot merge arguments generated by traits.
                     Path: [:role]
                     Value 1: :normal
                     Value 2: :admin
                   """,
                   fn -> produce(context, user: [:normal, :admin]) end

      # same entity with conflicting traits, deep map comparison
      assert_raise ArgumentError,
                   """
                   Cannot merge arguments generated by traits.
                     Path: [:finances, :plan]
                     Value 1: :paid
                     Value 2: :free
                   """,
                   fn -> produce(context, user: [:paid_plan, :free_plan]) end
    end

    test "accumulate traits using update instruction", context do
      # duplicating traits is not something that we really need,
      # but this test is present just to track the behaviour

      context =
        context
        |> produce(virtual_file: :virtual_file1)
        |> produce(virtual_file: :virtual_file2)
        |> assert_trait(:project, [:with_virtual_file, :with_virtual_file])

      context
      |> rebind([virtual_file: :virtual_file1], fn context ->
        context
        |> produce(project: [:with_virtual_file])
      end)
      |> assert_trait(:project, [:with_virtual_file, :with_virtual_file])
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
  end

  test "pre_produce", context do
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
  end

  defp assert_trait(context, binding_name, expected_traits) when is_list(expected_traits) do
    current_traits = Map.fetch!(context.__seed_factory_meta__.current_traits, binding_name)
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

    {new_context, %{added: added, deleted: deleted, updated: updated}}
  end
end
