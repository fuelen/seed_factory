defmodule SeedFactory.Transformers.VerifyTraitRequirements do
  @moduledoc false
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer

  def after?(module) do
    module in [
      SeedFactory.Transformers.IndexTraits,
      SeedFactory.Transformers.VerifyDependencies
    ]
  end

  def transform(dsl_state) do
    traits = Transformer.get_persisted(dsl_state, :traits)
    commands = Transformer.get_persisted(dsl_state, :commands)

    commands =
      Map.new(commands, fn {name, command} ->
        params = normalize_params(command.params, command, traits)

        command = %{
          command
          | params: params,
            required_entities: SeedFactory.Command.required_entities(params)
        }

        # Distinct params of one entity may still request conflicting values.
        for {entity, references} <- command.required_entities, MapSet.size(references) > 0 do
          ensure_consistent_values!(references, entity, command)
        end

        {name, command}
      end)

    {:ok, Transformer.persist(dsl_state, :commands, commands)}
  end

  defp normalize_params(params, command, traits) do
    Map.new(params, fn {key, parameter} ->
      parameter =
        case parameter do
          %{type: :container} ->
            %{parameter | params: normalize_params(parameter.params, command, traits)}

          %{type: :entity, with_traits: [_ | _] = references} ->
            %{
              parameter
              | with_traits: normalize!(references, parameter.entity, command, traits)
            }

          parameter ->
            parameter
        end

      {key, parameter}
    end)
  end

  defp normalize!(references, entity, command, traits) do
    by_name =
      case Map.fetch(traits, entity) do
        {:ok, %{by_name: by_name}} -> by_name
        :error -> raise SeedFactory.TraitNotFoundError, entity: entity
      end

    SeedFactory.Trait.normalize_references!(by_name, references, entity)
  rescue
    error in [ArgumentError, SeedFactory.UnknownTraitError, SeedFactory.TraitNotFoundError] ->
      raise_trait_error!(error, entity, command)
  end

  defp ensure_consistent_values!(references, entity, command) do
    SeedFactory.Trait.Value.ensure_consistent_values!(references, entity)
  rescue
    error in ArgumentError -> raise_trait_error!(error, entity, command)
  end

  defp raise_trait_error!(error, entity, command) do
    raise Spark.Error.DslError,
      path: [:root, :command, command.name, :with_traits, entity],
      message: Exception.message(error),
      location: Spark.Dsl.Entity.anno(command)
  end
end
