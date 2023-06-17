defmodule SeedFactory.DSL do
  @producing_instruction %Spark.Dsl.Entity{
    name: :produce,
    args: [:entity],
    target: SeedFactory.ProducingInstruction,
    schema: SeedFactory.ProducingInstruction.schema()
  }
  @updating_instruction %Spark.Dsl.Entity{
    name: :update,
    args: [:entity],
    target: SeedFactory.UpdatingInstruction,
    schema: SeedFactory.UpdatingInstruction.schema()
  }
  @deleting_instruction %Spark.Dsl.Entity{
    name: :delete,
    args: [:entity],
    target: SeedFactory.DeletingInstruction,
    schema: SeedFactory.DeletingInstruction.schema()
  }

  @param %Spark.Dsl.Entity{
    name: :param,
    recursive_as: :params,
    args: [:name, :source],
    entities: [params: []],
    transform: {SeedFactory.Parameter, :transform, []},
    target: SeedFactory.Parameter,
    schema: SeedFactory.Parameter.schema()
  }

  @command %Spark.Dsl.Entity{
    name: :command,
    args: [:name],
    entities: [
      params: [@param],
      producing_instructions: [@producing_instruction],
      updating_instructions: [@updating_instruction],
      deleting_instructions: [@deleting_instruction]
    ],
    transform: {SeedFactory.Command, :transform, []},
    target: SeedFactory.Command,
    schema: SeedFactory.Command.schema()
  }
  @root %Spark.Dsl.Section{
    name: :root,
    entities: [@command],
    top_level?: true
  }
  @sections [@root]

  @moduledoc false
  use Spark.Dsl.Extension,
    sections: @sections,
    transformers: [
      SeedFactory.Transformers.IndexCommands,
      SeedFactory.Transformers.IndexEntities,
      SeedFactory.Transformers.VerifyDependencies
    ]
end
