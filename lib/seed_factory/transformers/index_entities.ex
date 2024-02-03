defmodule SeedFactory.Transformers.IndexEntities do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def after?(module) do
    module == SeedFactory.Transformers.IncludeSchemas
  end

  def transform(dsl_state) do
    command_name_by_entity =
      dsl_state
      |> Transformer.get_persisted(:root)
      |> Enum.filter(&is_struct(&1, SeedFactory.Command))
      |> Enum.flat_map(fn command ->
        Enum.map(command.producing_instructions, fn instruction ->
          {instruction.entity, command.name}
        end)
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    {:ok, dsl_state |> Transformer.persist(:entities, command_name_by_entity)}
  end
end
