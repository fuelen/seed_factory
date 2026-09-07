# Prints one seed of a stress dump: the generated schema source and the
# recorded fields, so a diverging seed can be turned into a repro.
#
# Usage:
#   MIX_ENV=test mix run test/stress/scripts/show_seed.exs <dump.bin> <seed>
[path, seed_string] = System.argv()
dump = File.read!(path) |> :erlang.binary_to_term()
entry = Map.fetch!(dump, String.to_integer(seed_string))

entry
|> Map.take([:request, :steps, :outcome, :outcomes, :final, :satisfiable])
|> Enum.each(fn {key, value} -> IO.puts("#{key}: #{inspect(value)}") end)

case entry do
  %{source: source} -> IO.puts("\n#{source}")
  _ -> :ok
end
