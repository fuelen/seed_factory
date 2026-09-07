defmodule SeedFactory.TraitUpdaterCycleTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Minimized from rich stress seed 411. :make_beta_omega with :make_alpha
    # satisfies the request and adds :tagged on the way. :tagged is also
    # declared on the updater :tag_beta, and the resolution routes the trait
    # through it: the updater needs :beta, :make_beta_from_gamma produces it
    # from :gamma, and :make_gamma_omega produces :gamma from :beta. It raises
    # CircularDependencyError [:make_gamma_omega, :make_beta_from_gamma,
    # :tag_beta] instead of taking the first declared candidate. v0.8.2
    # planned make_beta_omega -> make_alpha.
    command :make_beta_omega do
      resolve(fn _ -> {:ok, %{beta: {:bo, :beta}, omega: {:bo, :omega}}} end)

      produce :beta
      produce :omega
    end

    command :make_gamma_omega do
      param :beta, entity: :beta

      resolve(fn _ -> {:ok, %{gamma: {:go, :gamma}, omega: {:go, :omega}}} end)

      produce :gamma
      produce :omega
    end

    command :make_gamma do
      resolve(fn _ -> {:ok, %{gamma: {:g, :gamma}}} end)

      produce :gamma
    end

    command :make_alpha do
      resolve(fn _ -> {:ok, %{alpha: {:a, :alpha}}} end)

      produce :alpha
    end

    command :tag_beta do
      param :beta, entity: :beta

      resolve(fn _ -> {:ok, %{beta: {:tb, :beta}}} end)

      update :beta
    end

    command :make_beta_from_gamma do
      param :gamma, entity: :gamma

      resolve(fn _ -> {:ok, %{beta: {:bg, :beta}}} end)

      produce :beta
    end

    trait :tagged, :beta do
      exec :make_beta_omega
    end

    trait :tagged, :beta do
      exec :tag_beta
    end
  end

  use SeedFactory.Test, schema: Schema
  import TraitAssertions

  test "a trait declared on a cycling updater is taken from the first declared command",
       context do
    context = produce(context, [:alpha, {:beta, [:tagged]}, :omega])

    assert Map.has_key?(context, :alpha)
    assert Map.has_key?(context, :omega)
    assert_trait(context, :beta, [:tagged])
  end
end
