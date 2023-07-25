defmodule SeedFactory.Transformers.IndexCommands do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def after?(module) do
    module == SeedFactory.Transformers.IncludeSchemas
  end

  def transform(dsl_state) do
    command_by_name =
      dsl_state
      |> Transformer.get_persisted(:root)
      |> Enum.filter(&is_struct(&1, SeedFactory.Command))
      |> tap(&ensure_unique_names/1)
      |> Map.new(&{&1.name, &1})

    {:ok, dsl_state |> Transformer.persist(:commands, command_by_name)}
  end

  defp ensure_unique_names(commands) do
    commands
    |> Enum.group_by(& &1.name)
    |> Enum.each(fn
      {_command_name, [_]} ->
        :ok

      {command_name, [_ | _]} ->
        raise Spark.Error.DslError,
          path: [:root, :command, command_name],
          message: "duplicated command name"
    end)
  end
end
