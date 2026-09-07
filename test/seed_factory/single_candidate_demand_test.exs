defmodule SeedFactory.SingleCandidateDemandTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use SeedFactory.Schema

    # Declaration order matters: :cmd_q is the first producer of :folio, so
    # without the demand from :report_a the head-order resolution would pick it
    # and remove :cmd_p, the only command able to produce :epsilon.
    command :cmd_q do
      resolve(fn _ -> {:ok, %{folio: :folio_q}} end)

      produce :folio
    end

    command :cmd_p do
      resolve(fn _ -> {:ok, %{folio: :folio_p, epsilon: :epsilon_p}} end)

      produce :folio
      produce :epsilon
    end

    command :report_a do
      param :epsilon, entity: :epsilon

      resolve(fn args -> {:ok, %{report: {:report_a, args.epsilon}}} end)

      produce :report
    end

    command :report_b do
      resolve(fn _ -> {:ok, %{report: :report_b}} end)

      produce :report
    end
  end

  use SeedFactory.Test, schema: Schema

  test "a demand from a conflicted command wins over the declaration order", context do
    # :report_a demands :epsilon while still sitting in the :report conflict
    # group. Once :report_a wins its group, the demand must force :cmd_p even
    # though :cmd_q is the first declared command producing :folio.
    context = produce(context, [:folio, :report])

    assert context.folio == :folio_p
    assert context.epsilon == :epsilon_p
    assert context.report == {:report_a, :epsilon_p}
  end

  test "the demand wins regardless of the request order", context do
    # With :report first, the :folio group is registered after the :report one
    # and must not be resolved before the demanding command settles.
    context = produce(context, [:report, :folio])

    assert context.folio == :folio_p
    assert context.report == {:report_a, :epsilon_p}
  end
end
