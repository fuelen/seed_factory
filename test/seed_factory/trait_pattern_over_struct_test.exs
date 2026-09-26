defmodule SeedFactory.TraitPatternOverStructTest do
  use ExUnit.Case, async: true
  import SeedFactory

  defmodule User do
    defstruct [:role]
  end

  defmodule Schema do
    use SeedFactory.Schema

    command :create_user do
      param :role, value: :admin

      resolve(fn args -> {:ok, %{user: %User{role: args.role}}} end)

      produce :user
    end

    command :create_post do
      param :user, entity: :user

      resolve(fn _ -> {:ok, %{post: :post}} end)

      produce :post
    end

    trait :by_admin, :post do
      exec :create_post, args_pattern: %{user: %{role: :admin}}
    end
  end

  test "a nested pattern reads the fields of a struct entity" do
    for {role, post_traits} <- [admin: [:by_admin], normal: []] do
      ctx = init(%{}, Schema) |> exec(:create_user, role: role) |> exec(:create_post)
      assert ctx.__seed_factory_meta__.current_traits.post == post_traits
    end
  end
end
