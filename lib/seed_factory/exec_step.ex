defmodule SeedFactory.ExecStep do
  @moduledoc false
  defstruct [
    :command_name,
    :args_pattern,
    :args_match,
    :generate_args
  ]

  @schema [
    command_name: [
      type: :atom,
      required: true,
      doc: "A name of the command"
    ],
    args_pattern: [type: :map],
    args_match: [type: {:fun, 1}],
    generate_args: [type: {:fun, 0}]
  ]

  def schema, do: @schema

  def transform(step) do
    cond do
      is_map(step.args_pattern) and
          (is_function(step.generate_args) or is_function(step.args_match)) ->
        {:error, "Option args_pattern cannot be used with generate_args and args_match options"}

      is_function(step.args_match) and is_nil(step.generate_args) ->
        {:error, "Option generate_args is required when args_match is specified"}

      is_function(step.generate_args) and is_nil(step.args_match) ->
        {:error, "Option args_match is required when generate_args` is specified"}

      true ->
        {:ok, step}
    end
  end
end
