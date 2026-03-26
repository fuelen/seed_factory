defmodule SeedFactory.Meta do
  @moduledoc false
  @derive {Inspect,
           only: [:entities_rebinding, :current_traits, :trails, :execution_history],
           optional: [:entities_rebinding, :current_traits, :trails, :execution_history]}
  defstruct [
    :entities,
    :commands,
    :traits,
    :create_dependent_entities?,
    :current_execution,
    entities_rebinding: %{},
    current_traits: %{},
    trails: %{},
    execution_history: []
  ]

  def new(schema) do
    %__MODULE__{
      create_dependent_entities?: true,
      traits: Spark.Dsl.Extension.get_persisted(schema, :traits),
      entities: Spark.Dsl.Extension.get_persisted(schema, :entities),
      commands: Spark.Dsl.Extension.get_persisted(schema, :commands)
    }
  end
end
