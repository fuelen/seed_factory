defmodule SeedFactory.DSL do
  @include_schema %Spark.Dsl.Entity{
    name: :include_schema,
    args: [:schema_module],
    target: SeedFactory.IncludeSchema,
    schema: SeedFactory.IncludeSchema.schema()
  }
  @producing_instruction %Spark.Dsl.Entity{
    name: :produce,
    args: [:entity],
    transform: {SeedFactory.ProducingInstruction, :transform, []},
    target: SeedFactory.ProducingInstruction,
    schema: SeedFactory.ProducingInstruction.schema()
  }
  @updating_instruction %Spark.Dsl.Entity{
    name: :update,
    args: [:entity],
    transform: {SeedFactory.UpdatingInstruction, :transform, []},
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
    args: [:name],
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

  @exec_step %Spark.Dsl.Entity{
    name: :exec,
    args: [:command_name],
    transform: {SeedFactory.ExecStep, :transform, []},
    target: SeedFactory.ExecStep,
    schema: SeedFactory.ExecStep.schema()
  }
  @trait %Spark.Dsl.Entity{
    name: :trait,
    args: [:name, :entity],
    entities: [exec_step: [@exec_step]],
    singleton_entity_keys: [:exec_step],
    target: SeedFactory.Trait,
    schema: SeedFactory.Trait.schema()
  }
  @root %Spark.Dsl.Section{
    name: :root,
    entities: [@command, @trait, @include_schema],
    top_level?: true
  }
  @sections [@root]

  @moduledoc false
  use Spark.Dsl.Extension,
    sections: @sections,
    transformers: [
      SeedFactory.Transformers.IncludeSchemas,
      SeedFactory.Transformers.IndexCommands,
      SeedFactory.Transformers.IndexEntities,
      SeedFactory.Transformers.IndexTraits,
      SeedFactory.Transformers.VerifyDependencies
    ]
end
