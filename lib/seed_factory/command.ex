defmodule SeedFactory.Command do
  @moduledoc false
  @derive {Inspect, only: []}

  defstruct [
    :name,
    :producing_instructions,
    :updating_instructions,
    :deleting_instructions,
    :resolve,
    :params
  ]

  @schema [
    name: [
      type: :atom,
      required: true,
      doc: "A name of the cmd"
    ],
    resolve: [
      type: {:fun, 1},
      required: true,
      doc: "Resolver function"
    ]
  ]

  def schema, do: @schema

  def transform(command) do
    ensure_instructions_present!(command)
    command = Map.update!(command, :params, &SeedFactory.Params.index_by_name/1)
    {:ok, command}
  end

  defp ensure_instructions_present!(command) do
    if command.producing_instructions == [] and command.updating_instructions == [] do
      raise Spark.Error.DslError,
        module: __MODULE__,
        path: [:commands, :command, command.name],
        message: "at least 1 produce or update directive must be set"
    end
  end
end
