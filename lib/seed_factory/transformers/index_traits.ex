defmodule SeedFactory.Transformers.IndexTraits do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def transform(dsl_state) do
    traits =
      dsl_state
      |> Transformer.get_entities([:root])
      |> Enum.filter(&is_struct(&1, SeedFactory.Trait))
      |> Enum.group_by(& &1.entity)
      |> Map.new(fn {entity, traits} ->
        ensure_unique_names(traits, entity)

        {entity,
         %{
           by_command_name: Enum.group_by(traits, & &1.exec_step.command_name),
           by_name: Map.new(traits, &{&1.name, &1})
         }}
      end)

    {:ok, dsl_state |> Transformer.persist(:traits, traits)}
  end

  defp ensure_unique_names(traits, entity) do
    traits
    |> Enum.group_by(& &1.name)
    |> Enum.each(fn
      {_trait_name, [_]} ->
        :ok

      {trait_name, [_ | _]} ->
        raise Spark.Error.DslError,
          path: [:root, :trait, trait_name, entity],
          message: "duplicated trait"
    end)
  end
end
