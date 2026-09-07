# Classifies the differences between two stress dumps of one generator.
#
# Usage:
#   MIX_ENV=test mix run test/stress/scripts/classify.exs <old.bin> <new.bin>
#
# Dumps come from the stress tests run with STRESS_OUT (see their headers);
# a differential gate runs the same generator in two checkouts (e.g. a git
# worktree on the previous release tag) and compares the dumps. Prints the
# frequency of every outcome transition at the first diverging step, then the
# suspicious rows: an ok that turned into a failure, or a new outcome that is
# neither ok nor a loud exception.
[old_path, new_path] = System.argv()
old = File.read!(old_path) |> :erlang.binary_to_term()
new = File.read!(new_path) |> :erlang.binary_to_term()

okish = fn
  :ok -> true
  {:ok, _} -> true
  _ -> false
end

loud = fn outcome -> match?({:raised, _}, outcome) end

short = fn
  {:raised, module} when is_atom(module) ->
    {:raised, module |> Module.split() |> List.last() |> String.to_atom()}

  {:ok, _} ->
    :ok

  other ->
    other
end

first_diff = fn old_outcome, new_outcome ->
  if is_list(old_outcome) and is_list(new_outcome) do
    Enum.zip(old_outcome, new_outcome) |> Enum.find(fn {a, b} -> a != b end)
  else
    if old_outcome != new_outcome do
      {old_outcome, new_outcome}
    else
      nil
    end
  end
end

get_outcome = fn entry -> Map.get(entry, :outcome, Map.get(entry, :outcomes)) end

rows =
  for seed <- Map.keys(new) |> Enum.sort(), old[seed] != new[seed] do
    case first_diff.(get_outcome.(old[seed]), get_outcome.(new[seed])) do
      nil -> {seed, :metadata_only, :metadata_only}
      {a, b} -> {seed, a, b}
    end
  end

IO.puts("entry diffs: #{length(rows)}")

rows
|> Enum.frequencies_by(fn {_seed, a, b} -> {short.(a), short.(b)} end)
|> Enum.sort_by(fn {_key, count} -> -count end)
|> Enum.each(fn {{a, b}, count} -> IO.puts("#{count}\t#{inspect(a)} -> #{inspect(b)}") end)

suspicious =
  for {seed, a, b} <- rows,
      a != :metadata_only,
      not okish.(b),
      okish.(a) or not loud.(b),
      do: {seed, short.(a), short.(b)}

IO.puts("suspicious: #{length(suspicious)}")

Enum.each(suspicious, fn {seed, a, b} ->
  IO.puts("  seed=#{seed} #{inspect(a)} -> #{inspect(b)}")
end)
