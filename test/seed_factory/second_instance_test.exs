defmodule SeedFactory.SecondInstanceTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Both producers of :contract also produce :contract_copy, so with an existing
    # :contract_copy every candidate would duplicate it.
    command :sign_contract do
      resolve(fn _ ->
        {:ok, %{contract: "signed contract", copy: "copy of signed contract"}}
      end)

      produce :contract
      produce :contract_copy, from: :copy
    end

    command :import_contract do
      resolve(fn _ ->
        {:ok, %{contract: "imported contract", copy: "copy of imported contract"}}
      end)

      produce :contract
      produce :contract_copy, from: :copy
    end

    command :appoint_notary do
      resolve(fn _ ->
        {:ok, %{notary: "notary"}}
      end)

      produce :notary
    end

    command :approve_contract do
      param :contract, entity: :contract
      param :notary, entity: :notary

      resolve(fn args ->
        {:ok, %{contract: args.contract <> " (approved)", approval: "approval"}}
      end)

      update :contract
      produce :approval
    end

    command :extend_contract do
      param :contract, entity: :contract

      resolve(fn args ->
        {:ok, %{contract: args.contract <> " (extended)"}}
      end)

      update :contract
    end

    command :notarize_contract do
      param :contract, entity: :contract

      resolve(fn args ->
        {:ok, %{contract: args.contract <> " (notarized)"}}
      end)

      update :contract
    end

    trait :approved, :contract do
      exec :approve_contract
    end

    trait :extended, :contract do
      from :approved
      exec :extend_contract
    end

    trait :notarized, :contract do
      exec :notarize_contract
    end
  end

  use SeedFactory.Test, schema: Schema

  import TraitAssertions

  test "produce with :as raises EntityAlreadyExistsError until all sibling entities are rebound",
       context do
    context = produce(context, contract: [:extended, :notarized])

    assert_trait(context, :contract, [:extended, :notarized])

    error =
      assert_raise SeedFactory.EntityAlreadyExistsError, fn ->
        produce(context, contract: [:extended, :notarized, as: :contract2])
      end

    assert error.entity == :contract_copy
    assert error.command == :sign_contract

    error =
      assert_raise SeedFactory.EntityAlreadyExistsError, fn ->
        produce(context,
          contract: [:extended, :notarized, as: :contract2],
          contract_copy: :contract_copy2
        )
      end

    assert error.entity == :approval
    assert error.command == :approve_contract

    context =
      produce(context,
        contract: [:extended, :notarized, as: :contract2],
        contract_copy: :contract_copy2,
        approval: :approval2
      )

    # The relative order of :approve_contract and :notarize_contract is not defined.
    assert context.contract2 =~ "signed contract"
    assert context.contract2 =~ "(approved)"
    assert context.contract2 =~ "(notarized)"
    assert context.contract2 =~ "(extended)"
    assert context.contract_copy2 == "copy of signed contract"
    assert context.approval2 == "approval"
    assert_trait(context, :contract2, [:extended, :notarized])
  end

  test "produce with rebinding raises EntityAlreadyExistsError when every producing command would duplicate an existing entity",
       context do
    context = produce(context, :contract)

    assert context.contract == "signed contract"

    error =
      assert_raise SeedFactory.EntityAlreadyExistsError, fn ->
        produce(context, contract: :contract2)
      end

    assert error.entity == :contract_copy
    assert error.command == :sign_contract
  end

  # :notary is rebound without being requested, so :appoint_notary can enter the
  # plan only through dependency collection of :approve_contract.
  test "produce plans rebound dependencies of an already-executed command", context do
    context = produce(context, contract: [:extended])

    error =
      assert_raise SeedFactory.EntityAlreadyExistsError, fn ->
        rebind(context, [notary: :notary2], fn context ->
          produce(context,
            contract: [:extended, as: :contract2],
            contract_copy: :contract_copy2
          )
        end)
      end

    assert error.entity == :approval
    assert error.command == :approve_contract
  end
end
