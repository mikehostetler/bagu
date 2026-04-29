defmodule Jidoka.Workflow.Runtime.Options do
  @moduledoc false

  alias Jidoka.Workflow.Runtime.Value

  @spec normalize(keyword()) :: {:ok, map()} | {:error, term()}
  def normalize(opts) do
    with {:ok, context} <- Jidoka.Context.normalize(Keyword.get(opts, :context, %{})),
         {:ok, agents} <- normalize_agents(Keyword.get(opts, :agents, %{})),
         {:ok, timeout} <- normalize_timeout(Keyword.get(opts, :timeout, 30_000)),
         {:ok, return} <- normalize_return(Keyword.get(opts, :return, :output)) do
      {:ok, %{context: context, agents: agents, timeout: timeout, return: return}}
    end
  end

  @spec parse_input(map(), map() | keyword()) :: {:ok, map()} | {:error, term()}
  def parse_input(definition, input) do
    with {:ok, input_map} <- coerce_input_map(input),
         {:ok, parsed} <- do_parse_input(definition, input_map) do
      {:ok, parsed}
    end
  end

  @spec validate_runtime_refs(map(), map()) :: :ok | {:error, term()}
  def validate_runtime_refs(definition, %{context: context, agents: agents}) do
    with :ok <- validate_context_refs(definition, context),
         :ok <- validate_imported_agent_refs(definition, agents) do
      :ok
    end
  end

  @spec initial_state(map(), map(), map()) :: map()
  def initial_state(definition, parsed_input, runtime_opts) do
    %{
      input: parsed_input,
      context: runtime_opts.context,
      agents: runtime_opts.agents,
      steps: %{},
      workflow_id: definition.id,
      timeout: runtime_opts.timeout
    }
  end

  defp normalize_agents(agents) when is_map(agents), do: {:ok, agents}

  defp normalize_agents(agents) when is_list(agents) do
    if Keyword.keyword?(agents) do
      {:ok, Map.new(agents)}
    else
      {:error, Jidoka.Error.validation_error("Invalid workflow agents: pass `agents:` as a map or keyword list.")}
    end
  end

  defp normalize_agents(other) do
    {:error,
     Jidoka.Error.validation_error("Invalid workflow agents: pass `agents:` as a map or keyword list.",
       field: :agents,
       value: other,
       details: %{reason: :expected_map}
     )}
  end

  defp normalize_timeout(timeout) when is_integer(timeout) and timeout > 0, do: {:ok, timeout}

  defp normalize_timeout(other) do
    {:error,
     Jidoka.Error.validation_error("Invalid workflow timeout: expected a positive integer.",
       field: :timeout,
       value: other,
       details: %{reason: :invalid_timeout}
     )}
  end

  defp normalize_return(return) when return in [:output, :debug], do: {:ok, return}

  defp normalize_return(other) do
    {:error,
     Jidoka.Error.validation_error("Invalid workflow return option: expected `:output` or `:debug`.",
       field: :return,
       value: other,
       details: %{reason: :invalid_return}
     )}
  end

  defp coerce_input_map(input) do
    case Jidoka.Context.coerce_map(input) do
      {:ok, map} ->
        {:ok, map}

      :error ->
        {:error,
         Jidoka.Error.validation_error("Invalid workflow input: pass input as a map or keyword list.",
           field: :input,
           value: input,
           details: %{reason: :expected_map}
         )}
    end
  end

  defp do_parse_input(definition, input_map) do
    case Zoi.parse(definition.input_schema, input_map) do
      {:ok, parsed} when is_map(parsed) ->
        {:ok, parsed}

      {:ok, other} ->
        {:error,
         Jidoka.Error.config_error("Workflow input schema must parse to a map.",
           field: :input_schema,
           value: other,
           details: %{workflow_id: definition.id, reason: :expected_map_result}
         )}

      {:error, errors} ->
        {:error,
         Jidoka.Error.validation_error("Invalid workflow input:\n" <> Zoi.prettify_errors(errors),
           field: :input,
           value: input_map,
           details: %{workflow_id: definition.id, reason: :schema, errors: Zoi.treefy_errors(errors)}
         )}
    end
  end

  defp validate_context_refs(definition, context) do
    Enum.reduce_while(definition.context_refs, :ok, fn key, :ok ->
      if Value.has_equivalent_key?(context, key) do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          Jidoka.Error.validation_error("Missing workflow context key `#{key}`.",
            field: :context,
            value: context,
            details: %{workflow_id: definition.id, reason: :missing_context, key: key}
          )}}
      end
    end)
  end

  defp validate_imported_agent_refs(definition, agents) do
    Enum.reduce_while(definition.imported_agent_refs, :ok, fn key, :ok ->
      if Value.has_equivalent_key?(agents, key) do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          Jidoka.Error.validation_error("Missing imported workflow agent `#{key}`.",
            field: :agents,
            value: agents,
            details: %{workflow_id: definition.id, reason: :missing_imported_agent, key: key}
          )}}
      end
    end)
  end
end
