defmodule SeedFactory.Trail do
  @moduledoc false
  defstruct [:produced_by, :updated_by]

  def new(produced_by) do
    %__MODULE__{produced_by: produced_by, updated_by: []}
  end

  def add_updated_by(trail, updated_by) do
    %{trail | updated_by: [updated_by | trail.updated_by]}
  end

  def to_map(%__MODULE__{produced_by: produced_by, updated_by: updated_by}) do
    Map.new([produced_by | updated_by], fn
      {action, added, removed} ->
        {action, %{added: added, removed: removed}}
    end)
  end

  def to_list(%__MODULE__{produced_by: produced_by, updated_by: updated_by}) do
    [produced_by | Enum.reverse(updated_by)]
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(trail, opts) do
      data = SeedFactory.Trail.to_list(trail)

      syntax_colors? = opts.syntax_colors != []

      parts =
        Enum.map_intersperse(data, " -> ", fn
          {action, [], []} ->
            to_doc(action, opts)

          {action, added, removed} ->
            action_doc = color(Atom.to_string(action), :atom, opts)

            plus =
              if syntax_colors?, do: IO.ANSI.green() <> "+" <> IO.ANSI.reset(), else: "+"

            added_doc = concat([plus, to_doc(added, opts)])

            removed_doc =
              case removed do
                [] ->
                  nil

                _ ->
                  minus =
                    if syntax_colors?, do: IO.ANSI.red() <> "-" <> IO.ANSI.reset(), else: "-"

                  concat([minus, to_doc(removed, opts)])
              end

            value_doc =
              [added_doc, removed_doc]
              |> Enum.reject(&is_nil/1)
              |> Enum.intersperse(" ")
              |> concat()

            concat([action_doc, ": ", value_doc])
        end)

      concat(["#trail[", concat(parts), "]"])
    end
  end
end
