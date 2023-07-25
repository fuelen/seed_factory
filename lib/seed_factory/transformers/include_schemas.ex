defmodule SeedFactory.Transformers.IncludeSchemas do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def transform(dsl_state) do
    {include_schemas, root} =
      dsl_state
      |> Transformer.get_entities([:root])
      |> Enum.split_with(&is_struct(&1, SeedFactory.IncludeSchema))

    root =
      Enum.reduce(include_schemas, root, fn %{schema_module: schema_module}, acc ->
        schema_module_root = Spark.Dsl.Extension.get_persisted(schema_module, :root)
        schema_module_root ++ acc
      end)

    {:ok, dsl_state |> Transformer.persist(:root, root)}
  end
end
