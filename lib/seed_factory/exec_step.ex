defmodule SeedFactory.ExecStep do
  @moduledoc false
  defstruct [
    :command_name,
    :args_pattern
  ]

  @schema [
    command_name: [
      type: :atom,
      required: true,
      doc: "A name of the command"
    ],
    args_pattern: [
      type: :map
    ]
  ]

  def schema, do: @schema
end
