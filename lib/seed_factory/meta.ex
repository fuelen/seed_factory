defmodule SeedFactory.Meta do
  @moduledoc false
  @derive {Inspect, only: [:entities_rebinding]}
  defstruct [:entities_rebinding, :entities, :commands]

  def new(schema) do
    %__MODULE__{
      entities_rebinding: nil,
      entities: Spark.Dsl.Extension.get_persisted(schema, :entities),
      commands: Spark.Dsl.Extension.get_persisted(schema, :commands)
    }
  end
end
