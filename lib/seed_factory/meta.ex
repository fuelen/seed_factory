defmodule SeedFactory.Meta do
  @moduledoc false
  @derive {Inspect,
           only: [:entities_rebinding, :current_traits, :trails],
           optional: [:entities_rebinding, :current_traits, :trails]}
  defstruct [
    :entities,
    :commands,
    :traits,
    :create_dependent_entities?,
    entities_rebinding: %{},
    current_traits: %{},
    trails: %{}
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
