defmodule SeedFactory.Execution do
  @moduledoc false
  defstruct [:caller, :commands, rebinding: %{}]

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(execution, opts) do
      caller_doc = format_caller(execution.caller, opts)
      commands_doc = format_commands(execution.commands, opts)

      rebinding_doc =
        if execution.rebinding == %{} do
          empty()
        else
          concat([" as ", to_doc(execution.rebinding, opts)])
        end

      concat(["#execution[", caller_doc, rebinding_doc, ": ", commands_doc, "]"])
    end

    defp format_caller({type, args}, opts) when is_list(args) do
      args_doc =
        args
        |> Enum.map(fn
          {key, value} -> concat([Atom.to_string(key), ": ", to_doc(value, opts)])
          atom when is_atom(atom) -> Atom.to_string(atom)
        end)
        |> Enum.intersperse(", ")
        |> concat()

      concat([Atom.to_string(type), "(", args_doc, ")"])
    end

    defp format_caller({type, name}, _opts) when is_atom(name) do
      concat([Atom.to_string(type), "(", Atom.to_string(name), ")"])
    end

    defp format_commands(commands, _opts) do
      commands
      |> Enum.reverse()
      |> Enum.map(&Atom.to_string/1)
      |> Enum.intersperse(" → ")
      |> concat()
    end
  end
end
