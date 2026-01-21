defmodule SeedFactory.DidYouMean do
  @moduledoc false

  @threshold 0.77

  def suggest(name, candidates) when is_atom(name) do
    name
    |> Atom.to_string()
    |> suggest(Enum.map(candidates, &Atom.to_string/1))
    |> case do
      nil -> nil
      suggestion -> String.to_existing_atom(suggestion)
    end
  end

  def suggest(name, candidates) when is_binary(name) do
    candidates
    |> Enum.map(&{&1, String.jaro_distance(name, &1)})
    |> Enum.filter(fn {_, score} -> score >= @threshold end)
    |> Enum.max_by(fn {_, score} -> score end, fn -> nil end)
    |> case do
      nil -> nil
      {suggestion, _score} -> suggestion
    end
  end

  def format_suggestion(nil), do: ""
  def format_suggestion(suggestion), do: ", did you mean #{inspect(suggestion)}?"
end

defmodule SeedFactory.UnknownEntityError do
  defexception [:message, :entity, :suggestion]

  def exception(opts) when is_list(opts) do
    entity = Keyword.fetch!(opts, :entity)
    available = Keyword.fetch!(opts, :available)

    suggestion = SeedFactory.DidYouMean.suggest(entity, available)

    message =
      "unknown entity #{inspect(entity)}" <>
        SeedFactory.DidYouMean.format_suggestion(suggestion)

    %__MODULE__{message: message, entity: entity, suggestion: suggestion}
  end
end

defmodule SeedFactory.UnknownCommandError do
  defexception [:message, :command, :suggestion]

  def exception(opts) when is_list(opts) do
    command = Keyword.fetch!(opts, :command)
    available = Keyword.fetch!(opts, :available)

    suggestion = SeedFactory.DidYouMean.suggest(command, available)

    message =
      "unknown command #{inspect(command)}" <>
        SeedFactory.DidYouMean.format_suggestion(suggestion)

    %__MODULE__{message: message, command: command, suggestion: suggestion}
  end
end

defmodule SeedFactory.TraitNotFoundError do
  defexception [:message, :entity]

  def exception(opts) when is_list(opts) do
    entity = Keyword.fetch!(opts, :entity)
    message = "entity #{inspect(entity)} has no defined traits"

    %__MODULE__{message: message, entity: entity}
  end
end

defmodule SeedFactory.EntityAlreadyExistsError do
  defexception [:message, :entity, :binding, :command, :traits]

  def exception(opts) when is_list(opts) do
    entity = Keyword.fetch!(opts, :entity)
    binding = Keyword.fetch!(opts, :binding)
    command = Keyword.fetch!(opts, :command)
    traits = Keyword.fetch!(opts, :traits)

    message_base =
      "cannot put entity #{inspect(entity)} to the context while executing #{inspect(command)}: " <>
        "key #{inspect(binding)} already exists"

    message =
      if traits == [] do
        message_base
      else
        "#{message_base}\n\ncurrent #{inspect(binding)} traits: #{inspect(traits)}"
      end

    %__MODULE__{
      message: message,
      entity: entity,
      binding: binding,
      command: command,
      traits: traits
    }
  end
end

defmodule SeedFactory.EntityNotFoundError do
  defexception [:message, :entity, :binding, :command, :operation]

  def exception(opts) when is_list(opts) do
    entity = Keyword.fetch!(opts, :entity)
    binding = Keyword.fetch!(opts, :binding)
    command = Keyword.fetch!(opts, :command)
    operation = Keyword.fetch!(opts, :operation)

    message =
      "cannot #{operation} entity #{inspect(entity)} while executing #{inspect(command)}: " <>
        "key #{inspect(binding)} doesn't exist in the context"

    %__MODULE__{
      message: message,
      entity: entity,
      binding: binding,
      command: command,
      operation: operation
    }
  end
end

defmodule SeedFactory.TraitRestrictionConflictError do
  defexception [:message, :entity, :binding, :traits, :required_by, :requested_traits]

  def exception(opts) when is_list(opts) do
    entity = Keyword.fetch!(opts, :entity)
    binding = Keyword.fetch!(opts, :binding)
    traits = Keyword.fetch!(opts, :traits)
    required_by = Keyword.fetch!(opts, :required_by)
    requested_traits = Keyword.fetch!(opts, :requested_traits)

    message =
      "cannot apply traits #{inspect(traits)} to #{inspect(binding)} as a requirement for #{inspect(required_by)} command, " <>
        "the entity was requested with the following traits: #{inspect(requested_traits)}"

    %__MODULE__{
      message: message,
      entity: entity,
      binding: binding,
      traits: traits,
      required_by: required_by,
      requested_traits: requested_traits
    }
  end
end

defmodule SeedFactory.TraitPathNotFoundError do
  defexception [
    :message,
    :entity,
    :binding,
    :required_traits,
    :conflicting_traits,
    :current_traits
  ]

  def exception(opts) when is_list(opts) do
    entity = Keyword.fetch!(opts, :entity)
    binding = Keyword.fetch!(opts, :binding)
    required_traits = Keyword.fetch!(opts, :required_traits)
    conflicting_traits = Keyword.fetch!(opts, :conflicting_traits)
    current_traits = Keyword.fetch!(opts, :current_traits)

    binding_label = format_binding(entity, binding)

    message =
      "cannot apply traits #{inspect(required_traits)} to #{binding_label}, " <>
        "there is no path from traits #{inspect(conflicting_traits)}, " <>
        "current traits: #{inspect(current_traits)}"

    %__MODULE__{
      message: message,
      entity: entity,
      binding: binding,
      required_traits: required_traits,
      conflicting_traits: conflicting_traits,
      current_traits: current_traits
    }
  end

  defp format_binding(entity, binding) when entity == binding, do: inspect(binding)
  defp format_binding(entity, binding), do: "#{inspect(binding)} (entity #{inspect(entity)})"
end

defmodule SeedFactory.TraitRemovedByCommandError do
  defexception [:message, :entity, :binding, :removed_traits, :command, :current_traits]

  def exception(opts) when is_list(opts) do
    entity = Keyword.fetch!(opts, :entity)
    binding = Keyword.fetch!(opts, :binding)
    removed_traits = Keyword.fetch!(opts, :removed_traits)
    command = Keyword.fetch!(opts, :command)
    current_traits = Keyword.fetch!(opts, :current_traits)

    binding_label = format_binding(entity, binding)

    message =
      "cannot apply traits #{inspect(removed_traits)} to #{binding_label} " <>
        "because they were removed by command #{inspect(command)}, " <>
        "current traits: #{inspect(current_traits)}"

    %__MODULE__{
      message: message,
      entity: entity,
      binding: binding,
      removed_traits: removed_traits,
      command: command,
      current_traits: current_traits
    }
  end

  defp format_binding(entity, binding) when entity == binding, do: inspect(binding)
  defp format_binding(entity, binding), do: "#{inspect(binding)} (entity #{inspect(entity)})"
end

defmodule SeedFactory.UnknownTraitError do
  defexception [:message, :entity, :trait, :suggestion]

  def exception(opts) when is_list(opts) do
    entity = Keyword.fetch!(opts, :entity)
    trait = Keyword.fetch!(opts, :trait)
    available = Keyword.fetch!(opts, :available)

    suggestion = SeedFactory.DidYouMean.suggest(trait, available)

    message =
      "entity #{inspect(entity)} doesn't have trait #{inspect(trait)}" <>
        SeedFactory.DidYouMean.format_suggestion(suggestion)

    %__MODULE__{message: message, entity: entity, trait: trait, suggestion: suggestion}
  end
end

defmodule SeedFactory.TraitResolutionError do
  defexception [:message, :entity, :trait, :required_by, :reason]

  def exception(opts) when is_list(opts) do
    entity = Keyword.fetch!(opts, :entity)
    trait = Keyword.fetch!(opts, :trait)
    required_by = Keyword.fetch!(opts, :required_by)
    reason = Keyword.fetch!(opts, :reason)

    message = build_message(entity, trait, required_by, reason)

    %__MODULE__{
      message: message,
      entity: entity,
      trait: trait,
      required_by: required_by,
      reason: reason
    }
  end

  defp build_message(entity_name, trait_name, required_by, reason) do
    context_label =
      case required_by do
        nil -> "requested trait"
        command -> "trait required by #{inspect(command)} command"
      end

    detail =
      reason
      |> reason_lines(0)
      |> Enum.join("\n")

    "cannot satisfy trait #{inspect(trait_name)} for entity #{inspect(entity_name)} (#{context_label})\n" <>
      detail
  end

  defp reason_lines({:commands_rejected, command_names}, indent) do
    unique_commands = Enum.uniq(command_names)

    case unique_commands do
      [single] ->
        [
          "#{indent_prefix(indent)}- candidate command #{inspect(single)} was previously rejected during conflict resolution"
        ]

      multiple ->
        commands = multiple |> Enum.map(&inspect/1) |> Enum.join(", ")

        [
          "#{indent_prefix(indent)}- all candidate commands [#{commands}] were previously rejected during conflict resolution"
        ]
    end
  end

  defp reason_lines(
         {:prerequisite_unsatisfied, trait_name, prerequisite, reason},
         indent
       ) do
    [
      "#{indent_prefix(indent)}- prerequisite trait #{inspect(prerequisite)} required by #{inspect(trait_name)} cannot be satisfied"
    ] ++ reason_lines(reason, indent + 2)
  end

  defp reason_lines({:trait_mismatch, trait, added, required_by}, indent) do
    label =
      case required_by do
        nil -> "specified trait"
        command_name -> "trait required by #{inspect(command_name)} command"
      end

    [
      "#{indent_prefix(indent)}- traits of previously executed command #{inspect(trait.exec_step.command_name)} do not match:",
      "#{indent_prefix(indent + 4)}previously applied traits: #{inspect(added)}",
      "#{indent_prefix(indent + 4)}#{label}: #{inspect(trait.name)}"
    ]
  end

  defp reason_lines({:all_traits_failed, errors}, indent) do
    [{:commands_rejected, commands} | rest_errors] = errors
    prerequisite_errors = rest_errors

    reason_lines({:commands_rejected, commands}, indent) ++
      Enum.flat_map(prerequisite_errors, &reason_lines(&1, indent))
  end

  defp indent_prefix(indent), do: String.duplicate(" ", indent)
end

defmodule SeedFactory.ConflictingTraitsError do
  defexception [:message, :conflicts]

  def exception(opts) when is_list(opts) do
    conflicts = Keyword.fetch!(opts, :conflicts)

    message =
      conflicts
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {entity, commands_with_traits} ->
        commands_description =
          commands_with_traits
          |> Enum.sort_by(&elem(&1, 0))
          |> Enum.map(fn {command, traits} ->
            trait_names = traits |> Enum.map(& &1.name) |> Enum.sort()
            "  - #{inspect(command)} (from traits #{inspect(trait_names)})"
          end)
          |> Enum.join("\n")

        "multiple requested traits produce the same entity #{inspect(entity)} via different commands:\n" <>
          commands_description
      end)
      |> Enum.join("\n\n")

    %__MODULE__{
      message: message,
      conflicts: conflicts
    }
  end
end
