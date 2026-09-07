defmodule SeedFactory.StressOutcomes do
  @moduledoc false

  # The outcome classes a stress run must never contain: a hang, a silently
  # incomplete result, a requested entity leaking into a pre_produce context,
  # or a raw crash from inside the planner. Loud SeedFactory exceptions are
  # legitimate outcomes for unsatisfiable programs and stay out of this list.
  def alarming(results) do
    for {seed, entry} <- results,
        outcome <- entry |> Map.get(:outcome, Map.get(entry, :outcomes)) |> List.wrap(),
        alarming?(outcome),
        do: {seed, outcome}
  end

  defp alarming?(outcome) do
    case outcome do
      :hang -> true
      {:silent_missing, _} -> true
      {:silent_missing, _, _} -> true
      {:pre_produced_requested, _} -> true
      {:raised, KeyError} -> true
      {:raised, FunctionClauseError} -> true
      {:raised, MatchError} -> true
      {:raised, BadMapError} -> true
      _ -> false
    end
  end
end
