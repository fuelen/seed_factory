defmodule SeedFactory.Trait.Value do
  @moduledoc false

  def fits?(nil, _value), do: true

  # Candidate selection only needs compatibility, not normalization or diagnostics.
  def fits?(params, value) when is_map(value) and not is_struct(value) do
    map_size(params) == map_size(value) and
      Enum.all?(params, fn {key, param} ->
        case Map.fetch(value, key) do
          {:ok, nested} -> param.type != :container or fits?(param.params, nested)
          :error -> false
        end
      end)
  end

  def fits?(params, value) when is_list(value) do
    Keyword.keyword?(value) and fits?(params, Map.new(value))
  end

  def fits?(_params, _value), do: false

  # References are already normalized; only conflicts across parameters remain.
  def ensure_consistent_values!(references, entity) do
    Enum.reduce(references, %{}, fn
      {name, value}, values -> put_value!(values, name, value, entity)
      _name, values -> values
    end)

    :ok
  end

  def put_value!(values, name, value, entity) do
    case Map.fetch(values, name) do
      {:ok, previous} when previous !== value ->
        raise ArgumentError,
              "conflicting values for trait #{inspect(name)} of entity #{inspect(entity)}: #{inspect([previous, value])}"

      _ ->
        Map.put(values, name, value)
    end
  end

  # A placeholder on a param with nested params receives a map built by the
  # same rules as the command's input, and each missing nested key would be
  # filled by a default the request cannot match. Declarations of one trait
  # may take different shapes, so the value has to fit one of them, and a
  # container shape wins over a plain param that would take the value as is.
  def normalize!(declarations, name, value, entity) do
    result =
      Enum.reduce_while(declarations, :no_match, fn %{exec_step: step}, fallback ->
        case step.value_params do
          nil ->
            {:cont, :plain}

          params ->
            case normalize_container(params, value, []) do
              {map, []} -> {:halt, {:ok, map}}
              {_map, _problems} -> {:cont, fallback}
            end
        end
      end)

    case result do
      {:ok, map} -> map
      :plain -> value
      :no_match -> raise_value_error!(declarations, name, value, entity)
    end
  end

  defp raise_value_error!(declarations, name, value, entity) do
    failures =
      Enum.map(declarations, fn %{exec_step: step} ->
        {_map, problems} = normalize_container(step.value_params, value, [])
        {step.command_name, container_error(problems, step.value_path)}
      end)
      |> Enum.uniq_by(fn {_command, problem} -> problem end)

    case failures do
      [{_command, problem}] ->
        raise ArgumentError, "trait #{inspect(name)} of entity #{inspect(entity)} #{problem}"

      failures ->
        lines = for {command, problem} <- failures, do: "\n  * #{inspect(command)} #{problem}"

        raise ArgumentError,
              "trait #{inspect(name)} of entity #{inspect(entity)} fits no declaration:" <>
                Enum.join(lines)
    end
  end

  defp container_error(problems, value_path) do
    param = format_key_path(value_path)

    case Enum.find(problems, &match?({:not_map, _, _}, &1)) do
      {:not_map, [], value} ->
        "expects a map or a keyword list for param #{param}, got: #{inspect(value)}"

      {:not_map, path, value} ->
        "expects a map or a keyword list at #{format_key_path(path)} of param #{param}, got: #{inspect(value)}"

      nil ->
        format_key_problems(problems, param)
    end
  end

  defp normalize_container(params, value, path) do
    cond do
      is_map(value) and not is_struct(value) ->
        normalize_keys(params, value, path)

      is_list(value) and Keyword.keyword?(value) ->
        normalize_keys(params, Map.new(value), path)

      true ->
        {value, [{:not_map, path, value}]}
    end
  end

  defp normalize_keys(params, map, path) do
    unknown = for key <- Map.keys(map), not is_map_key(params, key), do: {:unknown, path ++ [key]}

    Enum.reduce(params, {map, unknown}, fn {key, param}, {map, problems} ->
      case {param.type, Map.fetch(map, key)} do
        {_type, :error} ->
          {map, [{:missing, path ++ [key]} | problems]}

        {:container, {:ok, nested}} ->
          {nested, nested_problems} = normalize_container(param.params, nested, path ++ [key])
          {Map.put(map, key, nested), nested_problems ++ problems}

        {_type, {:ok, _value}} ->
          {map, problems}
      end
    end)
  end

  defp format_key_problems(problems, param) do
    [
      missing: "needs every nested key of param #{param}, missing",
      unknown: "got keys that param #{param} does not define"
    ]
    |> Enum.flat_map(fn {kind, text} ->
      case for({^kind, path} <- problems, do: path) do
        [] -> []
        paths -> ["#{text}: " <> Enum.map_join(Enum.sort(paths), ", ", &format_key_path/1)]
      end
    end)
    |> Enum.join("; ")
  end

  defp format_key_path([key]), do: inspect(key)
  defp format_key_path(path), do: inspect(path)
end
