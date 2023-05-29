defmodule SeedFactoryTest do
  use ExUnit.Case, async: true
  use SeedFactory.Test, schema: SchemaExample

  test "rebind", context do
    {context, diff} =
      with_diff(context, fn ->
        context
        |> rebind([office: :office1, user: :user1], fn context ->
          context
          |> exec(:create_office, name: "My Office #1")
          |> exec(:create_user, name: "John Doe")
        end)
        |> rebind([office: :office2, user: :user2], fn context ->
          context
          |> exec(:create_office, name: "My Office #2")
          |> produce([:user])
        end)
      end)

    assert diff == %{
             added: [:office1, :office2, :org, :user1, :user2],
             deleted: [],
             updated: []
           }

    assert context.office1.name == "My Office #1"
    assert context.office2.name == "My Office #2"
    assert context.user1.name == "John Doe"
  end

  test "nested rebinging is not supported", context do
    assert_raise RuntimeError, "Nested rebinding is not supported", fn ->
      rebind(context, [org: :org1], fn context ->
        rebind(context, [org: :org2], fn context ->
          produce(context, [:org])
        end)
      end)
    end
  end

  test "resolver returns error", context do
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
    assert diff == %{added: [:office, :org, :user], deleted: [], updated: []}

    {context, diff} = with_diff(context, fn -> exec(context, :activate_user) end)
    assert diff == %{added: [], deleted: [], updated: [:user]}
    assert context.user.status == :active
  end

  test "updating a non-existing value", context do
    context = produce(context, :user)
    {user, context} = Map.pop!(context, :user)

    assert_raise RuntimeError,
                 "Cannot update entity :user: key :user doesn't exist in the context",
                 fn ->
                   exec(context, :activate_user, user: user)
                 end
  end

  test "deleting a value from the context", context do
    {context, diff} = with_diff(context, fn -> produce(context, [:draft_project]) end)
    assert diff == %{added: [:draft_project, :office, :org], deleted: [], updated: []}
    {_context, diff} = with_diff(context, fn -> produce(context, [:project]) end)
    assert diff == %{added: [:project], deleted: [:draft_project], updated: []}
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

  test "create entity specified as an atom", context do
    {_context, diff} = with_diff(context, fn -> produce(context, :project) end)
    assert diff == %{added: [:office, :org, :project], deleted: [], updated: []}
  end

  test "create entities specified as a simple list", context do
    {_context, diff} = with_diff(context, fn -> produce(context, [:draft_project, :user]) end)
    assert diff == %{added: [:draft_project, :office, :org, :user], deleted: [], updated: []}
  end

  test "create entities with rebinding", context do
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

    assert diff == %{added: [:office3, :project1, :project2], deleted: [], updated: []}
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

  test "double execution of the same command", context do
    assert_raise RuntimeError,
                 "Cannot put entity :org to the context: key :org already exists",
                 fn ->
                   context
                   |> exec(:create_org)
                   |> exec(:create_org)
                 end
  end

  test "redundant parameters", context do
    assert_raise RuntimeError,
                 "Input doesn't match defined params. Redundant keys found: [:unknown_param1, :unknown_param2]",
                 fn ->
                   context
                   |> exec(:create_org,
                     unknown_param1: "heey",
                     name: "QWERTY",
                     unknown_param2: "heey2"
                   )
                 end
  end

  def with_diff(context, callback) do
    initial_context_keys = Map.keys(context)
    new_context = callback.()
    new_context_keys = Map.keys(new_context)

    added = new_context_keys -- initial_context_keys
    deleted = initial_context_keys -- new_context_keys

    updated =
      Enum.reject(new_context_keys -- added, fn element ->
        context[element] == new_context[element]
      end)

    {new_context, %{added: added, deleted: deleted, updated: updated}}
  end
end
