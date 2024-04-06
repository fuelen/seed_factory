defmodule SeedFactory.Trail do
  @moduledoc false
  defstruct [
    :produced_by,
    :updated_by
  ]

  def new(produced_by) do
    %__MODULE__{produced_by: produced_by, updated_by: []}
  end

  def add_updated_by(trail, updated_by) do
    %{trail | updated_by: [updated_by | trail.updated_by]}
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(%SeedFactory.Trail{produced_by: produced_by, updated_by: updated_by}, opts) do
      data = [produced_by | Enum.reverse(updated_by)]
      open = color("[", :list, opts)
      sep = color(" ->", :list, opts)
      close = color("]", :list, opts)
      doc = container_doc(open, data, close, opts, &to_doc/2, separator: sep)
      concat(["#trail", doc])
    end
  end
end
