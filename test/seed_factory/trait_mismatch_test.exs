defmodule SeedFactory.TraitMismatchTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Both commands produce :document, forming a conflict group. The verified
    # variant requires :profile with a trait that only exists at creation, so
    # with a profile already created without it that command cannot be satisfied.
    command :create_profile do
      param :contacts_confirmed?, value: false

      resolve(fn args ->
        {:ok, %{profile: %{contacts_confirmed?: args.contacts_confirmed?}}}
      end)

      produce :profile
    end

    command :create_document do
      param :profile, entity: :profile

      resolve(fn args ->
        {:ok, %{document: %{profile: args.profile, verified_profile?: false}}}
      end)

      produce :document
    end

    command :create_document_for_verified_profile do
      param :profile, entity: :profile, with_traits: [:contacts_confirmed]

      resolve(fn args ->
        {:ok, %{document: %{profile: args.profile, verified_profile?: true}}}
      end)

      produce :document
    end

    trait :contacts_confirmed, :profile do
      exec :create_profile, args_pattern: %{contacts_confirmed?: true}
    end
  end

  use SeedFactory.Test, schema: Schema

  test "removes command from conflict group when trait cannot be satisfied", context do
    context =
      context
      |> produce(:profile)
      |> produce(:document)

    assert context.profile.contacts_confirmed? == false
    assert context.document.verified_profile? == false
  end
end
