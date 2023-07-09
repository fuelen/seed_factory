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
    ensure_instructions_are_unique_per_entity!(command)
    command = Map.update!(command, :params, &SeedFactory.Params.index_by_name/1)
    {:ok, command}
  end

  defp ensure_instructions_present!(command) do
    if command.producing_instructions == [] and command.updating_instructions == [] and
         command.deleting_instructions == [] do
      raise Spark.Error.DslError,
        module: __MODULE__,
        path: [:root, :command, command.name],
        message: "at least 1 produce, update or delete directive must be set"
    end
  end

  defp ensure_instructions_are_unique_per_entity!(command) do
    (command.deleting_instructions ++
       command.producing_instructions ++ command.updating_instructions)
    |> Enum.group_by(& &1.entity)
    |> Enum.each(fn
      {_entity, [_]} ->
        :ok

      {entity, [_ | _]} ->
        raise Spark.Error.DslError,
          module: __MODULE__,
          path: [:root, :command, command.name],
          message: "cannot apply multiple instructions on the same entity (#{inspect(entity)})"
    end)
  end
end
