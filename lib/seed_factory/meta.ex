defmodule SeedFactory.Meta do
  @moduledoc false
  @derive {Inspect, only: [:entities_rebinding, :current_traits]}
  defstruct [
    :entities_rebinding,
    :entities,
    :commands,
    :traits,
    :current_traits,
    :create_dependent_entities?
  ]

  def new(schema) do
    %__MODULE__{
      entities_rebinding: %{},
      current_traits: %{},
      create_dependent_entities?: true,
      traits: Spark.Dsl.Extension.get_persisted(schema, :traits),
      entities: Spark.Dsl.Extension.get_persisted(schema, :entities),
      commands: Spark.Dsl.Extension.get_persisted(schema, :commands)
    }
  end
end
