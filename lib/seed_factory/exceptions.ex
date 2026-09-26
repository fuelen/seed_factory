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
      case required_by do
        nil ->
          "cannot apply traits #{inspect(traits)} to #{inspect(binding)}, requested with the traits " <>
            "#{inspect(requested_traits)}: applying them would replace a requested trait"

        command ->
          "cannot apply traits #{inspect(traits)} to #{inspect(binding)} as a requirement for #{inspect(command)} command, " <>
            "the entity was requested with the following traits: #{inspect(requested_traits)}"
      end

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

defmodule SeedFactory.MissingRequestedTraitError do
  defexception [
    :message,
    :entity,
    :binding,
    :trait,
    :required_by,
    :removed_by,
    :removed_when,
    :assigned_value
  ]

  # Raised by the prediction of the required traits' delivery, before the
  # first step after which the trait cannot come back. `required_by` is the
  # planned command whose parameter asks for the trait, nil for the request.
  # `removed_when` says whether the remover is a planned step or one this plan
  # already ran while a later re-add was still uncertain, or `:assigned` when
  # a planned step gives the parameterized trait `assigned_value` instead.
  def exception(opts) when is_list(opts) do
    entity = Keyword.fetch!(opts, :entity)
    binding = Keyword.fetch!(opts, :binding)
    trait = Keyword.fetch!(opts, :trait)
    required_by = Keyword.fetch!(opts, :required_by)
    removed_by = Keyword.fetch!(opts, :removed_by)
    removed_when = Keyword.fetch!(opts, :removed_when)
    assigned_value = Keyword.get(opts, :assigned_value)

    binding_label = format_binding(entity, binding)

    subject =
      case required_by do
        nil ->
          "requested trait #{inspect(trait)} would be missing on #{binding_label} after the plan"

        command ->
          "trait #{inspect(trait)} required by #{inspect(command)} would be missing on " <>
            "#{binding_label} when it runs"
      end

    cause =
      case {removed_by, removed_when} do
        {nil, _} ->
          "no planned command applies it"

        {command, :planned} ->
          "command #{inspect(command)} removes it"

        {command, :assigned} ->
          "command #{inspect(command)} assigns #{inspect(assigned_value)} instead"

        {command, :executed} ->
          "command #{inspect(command)} removed it and no later planned command applies it"
      end

    %__MODULE__{
      message: subject <> ": " <> cause,
      entity: entity,
      binding: binding,
      trait: trait,
      required_by: required_by,
      removed_by: removed_by,
      removed_when: removed_when,
      assigned_value: assigned_value
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

  defp reason_lines({:commands_rejected, rejections}, indent) do
    rejections
    |> Enum.uniq()
    |> Enum.map(fn {command, reason} ->
      "#{indent_prefix(indent)}- candidate command #{inspect(command)} " <>
        SeedFactory.RejectionReason.clause(reason)
    end)
  end

  defp reason_lines(
         {:prerequisite_unsatisfied, trait_name, prerequisite, reason},
         indent
       ) do
    [
      "#{indent_prefix(indent)}- prerequisite trait #{inspect(prerequisite)} required by #{inspect(trait_name)} cannot be satisfied"
    ] ++ reason_lines(reason, indent + 2)
  end

  defp reason_lines({:trait_mismatch, executed_traits, required_by}, indent) do
    label =
      case required_by do
        nil -> "specified trait"
        command_name -> "trait required by #{inspect(command_name)} command"
      end

    Enum.flat_map(executed_traits, fn {trait, added} ->
      [
        "#{indent_prefix(indent)}- traits of previously executed command #{inspect(trait.exec_step.command_name)} do not match:",
        "#{indent_prefix(indent + 4)}previously applied traits: #{inspect(added)}",
        "#{indent_prefix(indent + 4)}#{label}: #{inspect(trait.name)}"
      ]
    end)
  end

  defp reason_lines({:removed_by_command, command, via_trait, removed_trait}, indent) do
    [
      "#{indent_prefix(indent)}- command #{inspect(command)}, chosen for the plan, " <>
        "applies #{inspect(via_trait)} and removes #{inspect(removed_trait)}"
    ]
  end

  defp reason_lines({:re_produced_without, command, entity, trait}, indent) do
    [
      "#{indent_prefix(indent)}- command #{inspect(command)}, chosen for the plan, " <>
        "re-produces #{inspect(entity)} without #{inspect(trait)}"
    ]
  end

  defp reason_lines({:all_traits_failed, errors}, indent) do
    Enum.flat_map(errors, &reason_lines(&1, indent))
  end

  defp indent_prefix(indent), do: String.duplicate(" ", indent)
end

defmodule SeedFactory.ExecError do
  defexception [
    :command,
    :exception,
    :error,
    :stacktrace,
    :execution_plan,
    :trails,
    :current_traits
  ]

  @impl true
  def message(%__MODULE__{} = error) do
    [
      header(error),
      execution_plan_section(error.execution_plan),
      trails_section(error.trails),
      current_traits_section(error.current_traits),
      original_exception_section(error.exception)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp header(%{exception: exception, command: command}) when exception != nil do
    "exception in #{inspect(command)} command"
  end

  defp header(%{error: error, command: command}) do
    "unable to execute #{inspect(command)} command: #{inspect(error)}"
  end

  defp execution_plan_section(nil), do: nil

  defp execution_plan_section(plan) do
    items =
      Enum.map_join(plan, "\n", fn
        {command, :completed} -> "  \u2714 #{inspect(command)}"
        {command, :failed} -> "  \u2716 #{inspect(command)}"
        {command, :pending} -> "  \u00b7 #{inspect(command)}"
      end)

    "Execution plan:\n" <> items
  end

  defp trails_section(trails) when trails == %{}, do: nil

  defp trails_section(trails) do
    items =
      trails
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join("\n", fn {binding, trail} ->
        "  #{binding}: #{inspect(trail, syntax_colors: [])}"
      end)

    "Trails:\n" <> items
  end

  defp current_traits_section(traits) when traits == %{}, do: nil

  defp current_traits_section(traits) do
    "Current traits:\n  #{inspect(traits, custom_options: [sort_maps: true])}"
  end

  defp original_exception_section(nil), do: nil

  defp original_exception_section(exception) do
    "Original exception:\n  #{Exception.format_banner(:error, exception)}"
  end
end

defmodule SeedFactory.CircularDependencyError do
  defexception [:message, :commands]

  def exception(opts) when is_list(opts) do
    commands = opts |> Keyword.fetch!(:commands) |> Enum.sort()

    message = "commands have circular dependencies: #{inspect(commands)}"

    %__MODULE__{message: message, commands: commands}
  end
end

defmodule SeedFactory.RejectionReason do
  @moduledoc false

  # Renders, as a clause following the command name, why the solver refused a
  # candidate command.
  def clause({:would_duplicate, entity}) do
    "would duplicate existing #{inspect(entity)} (rebind or delete it first)"
  end

  def clause({:produce_conflict, entity, other_command}) do
    "also produces #{inspect(entity)}, already produced by #{inspect(other_command)} in this plan"
  end

  def clause({:deletes_requested, entity}) do
    "deletes requested #{inspect(entity)}"
  end

  def clause({:self_consuming, entity}) do
    "both requires and produces #{inspect(entity)}, so it can never run as a dependency"
  end

  def clause({:cycle, demander}) do
    "transitively requires #{inspect(demander)}, which would form a cycle"
  end

  def clause(:own_trait_demand) do
    "demands the trait it provides"
  end

  def clause(:prerequisite_failed) do
    "failed on the prerequisites below"
  end

  def clause({:lost_to, trait, winner}) do
    "lost the #{inspect(trait)} resolution to #{inspect(winner)} in this plan"
  end

  def clause({:args_conflict, path, fixed_value, fixed_trait, value}) do
    key = Enum.map_join(path, ".", &to_string/1)

    "already runs with #{key}: #{inspect(fixed_value)} for trait #{inspect(fixed_trait)}, " <>
      "which conflicts with #{key}: #{inspect(value)}"
  end

  def clause({:collection, exception}) do
    "was rejected by a parameter check (#{exception.__struct__ |> Module.split() |> List.last()})"
  end
end

defmodule SeedFactory.UnproducibleEntityError do
  defexception [:message, :entity, :required_by, :commands, :cause, :rejections]

  def exception(opts) when is_list(opts) do
    entity = Keyword.fetch!(opts, :entity)
    required_by = Keyword.fetch!(opts, :required_by)
    commands = Keyword.fetch!(opts, :commands)
    cause = Keyword.get(opts, :cause, :rejected)
    rejections = Keyword.get(opts, :rejections)

    required_by_part = if required_by, do: " required by #{inspect(required_by)}", else: ""

    # :not_planned lists candidates that may have never entered the plan, so it
    # must not claim they were rejected. :over_deleted and :unorderable list
    # the commands that cannot share the entity's instances;
    # :deleted_before_consumer the one deleter the consumer depends on.
    cause_part =
      case cause do
        :rejected ->
          "no candidate command fits the plan\n" <> rejection_lines(rejections)

        :not_planned ->
          "no command able to produce it is part of the execution plan: " <> inspect(commands)

        :over_deleted ->
          "it sits in the context once, but the plan deletes it more than once: " <>
            inspect(commands)

        :unorderable ->
          "the commands producing and deleting it cannot interleave produce → delete → produce: " <>
            inspect(commands)

        :deleted_before_consumer ->
          "command #{inspect(hd(commands))}, chosen for the plan, deletes it before " <>
            "#{inspect(required_by)} runs"
      end

    message = "cannot produce entity #{inspect(entity)}#{required_by_part}: " <> cause_part

    %__MODULE__{
      message: message,
      entity: entity,
      required_by: required_by,
      commands: commands,
      cause: cause,
      rejections: rejections
    }
  end

  defp rejection_lines(rejections) do
    Enum.map_join(rejections, "\n", fn {command, reason} ->
      "- #{inspect(command)} #{SeedFactory.RejectionReason.clause(reason)}"
    end)
  end
end
