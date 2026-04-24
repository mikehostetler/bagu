defmodule Jidoka do
  @moduledoc """
  Minimal runtime facade for starting and discovering Jidoka agents.
  """

  alias Jido.AI.Request
  alias Jidoka.ImportedAgent

  @doc """
  Returns Jidoka-owned model aliases from application config.

  These aliases are defined under `config :jidoka, :model_aliases`.
  """
  @spec model_aliases() :: %{optional(atom()) => term()}
  def model_aliases do
    case Application.get_env(:jidoka, :model_aliases, %{}) do
      aliases when is_map(aliases) -> aliases
      _ -> %{}
    end
  end

  @doc """
  Normalizes a model input using Jidoka aliases first, then Jido.AI.
  """
  @spec model(Jido.AI.model_input()) :: ReqLLM.model_input()
  def model(model) when is_atom(model) do
    case model_aliases() do
      %{^model => resolved} -> resolved
      _ -> Jido.AI.resolve_model(model)
    end
  end

  def model(model) when is_binary(model) do
    trimmed = String.trim(model)

    case resolve_string_alias(trimmed) do
      {:ok, alias_name} -> model(alias_name)
      :error -> Jido.AI.resolve_model(trimmed)
    end
  end

  def model(model), do: Jido.AI.resolve_model(model)

  @doc """
  Starts an agent under the shared `Jidoka.Runtime` instance.
  """
  def start_agent(agent, opts \\ [])

  @spec start_agent(ImportedAgent.t(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_agent(%ImportedAgent{} = agent, opts), do: ImportedAgent.start_link(agent, opts)

  @spec start_agent(module() | struct(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_agent(agent, opts), do: Jidoka.Runtime.start_agent(agent, opts)

  @doc """
  Stops an agent by PID or registered ID.
  """
  @spec stop_agent(pid() | String.t(), keyword()) :: :ok | {:error, :not_found}
  def stop_agent(pid_or_id, opts \\ []), do: Jidoka.Runtime.stop_agent(pid_or_id, opts)

  @doc """
  Looks up a running agent by ID.
  """
  @spec whereis(String.t(), keyword()) :: pid() | nil
  def whereis(id, opts \\ []), do: Jidoka.Runtime.whereis(id, opts)

  @doc """
  Lists all running agents.
  """
  @spec list_agents(keyword()) :: [{String.t(), pid()}]
  def list_agents(opts \\ []), do: Jidoka.Runtime.list_agents(opts)

  @doc """
  Imports a constrained Jidoka agent from a map, JSON string, or YAML string.

  The imported format mirrors the beta DSL sections: `agent`, `defaults`,
  `capabilities`, and `lifecycle`.

  Imported tools and plugins must be resolved through the explicit
  `:available_tools`, `:available_subagents`, `:available_plugins`,
  `:available_hooks`, and
  `:available_guardrails` registries passed in `opts`.
  """
  @spec import_agent(map() | binary(), keyword()) :: {:ok, ImportedAgent.t()} | {:error, term()}
  def import_agent(source, opts \\ []), do: ImportedAgent.import(source, opts)

  @doc """
  Imports a constrained Jidoka agent and raises on failure.
  """
  @spec import_agent!(map() | binary(), keyword()) :: ImportedAgent.t()
  def import_agent!(source, opts \\ []) do
    case import_agent(source, opts) do
      {:ok, agent} -> agent
      {:error, reason} -> raise ArgumentError, message: ImportedAgent.format_error(reason)
    end
  end

  @doc """
  Imports a constrained Jidoka agent from a `.json`, `.yaml`, or `.yml` file.
  """
  @spec import_agent_file(Path.t(), keyword()) :: {:ok, ImportedAgent.t()} | {:error, term()}
  def import_agent_file(path, opts \\ []), do: ImportedAgent.import_file(path, opts)

  @doc """
  Imports a constrained Jidoka agent from a file and raises on failure.
  """
  @spec import_agent_file!(Path.t(), keyword()) :: ImportedAgent.t()
  def import_agent_file!(path, opts \\ []) do
    case import_agent_file(path, opts) do
      {:ok, agent} -> agent
      {:error, reason} -> raise ArgumentError, message: ImportedAgent.format_error(reason)
    end
  end

  @doc """
  Encodes an imported Jidoka agent as JSON or YAML.
  """
  @spec encode_agent(ImportedAgent.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def encode_agent(agent, opts \\ [])
  def encode_agent(%ImportedAgent{} = agent, opts), do: ImportedAgent.encode(agent, opts)

  @doc """
  Formats Jidoka error terms for humans.

  Use this helper when presenting Jidoka errors in CLIs, demos, logs, or tests.
  """
  @spec format_error(term()) :: String.t()
  def format_error(reason), do: Jidoka.Error.format(reason)

  @doc """
  Encodes an imported Jidoka agent as JSON or YAML and raises on failure.
  """
  @spec encode_agent!(ImportedAgent.t(), keyword()) :: binary()
  def encode_agent!(agent, opts \\ [])

  def encode_agent!(%ImportedAgent{} = agent, opts) do
    case encode_agent(agent, opts) do
      {:ok, encoded} -> encoded
      {:error, reason} -> raise ArgumentError, message: ImportedAgent.format_error(reason)
    end
  end

  @doc """
  Sends a chat request to a running Jidoka agent and waits for the result.

  Accepts a PID, server reference, or Jidoka agent ID string.
  """
  @spec chat(pid() | atom() | {:via, module(), term()} | String.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, term()} | {:interrupt, Jidoka.Interrupt.t()} | {:handoff, Jidoka.Handoff.t()}
  def chat(server_or_id, message, opts \\ []) when is_binary(message) do
    with {:ok, request} <- start_chat_request(server_or_id, message, opts) do
      await_chat_request(request, opts)
    end
  end

  @doc false
  @spec start_chat_request(pid() | atom() | {:via, module(), term()} | String.t(), String.t(), keyword()) ::
          {:ok, Request.Handle.t()} | {:error, term()}
  def start_chat_request(server_or_id, message, opts \\ []) when is_binary(message) and is_list(opts) do
    result =
      with :ok <- validate_conversation_opt(opts),
           {:ok, target} <- route_conversation_owner(server_or_id, opts),
           {:ok, server} <- resolve_server(target, opts),
           {:ok, prepared_opts} <- Jidoka.Agent.prepare_chat_opts(opts, chat_config(server)) do
        request_opts = Keyword.merge(prepared_opts, signal_type: "ai.react.query", source: "/jidoka/agent")

        Request.create_and_send(server, message, request_opts)
      end

    normalize_start_chat_result(result, server_or_id, opts)
  end

  @doc false
  @spec await_chat_request(Request.Handle.t(), keyword()) ::
          {:ok, term()} | {:error, term()} | {:interrupt, Jidoka.Interrupt.t()} | {:handoff, Jidoka.Handoff.t()}
  def await_chat_request(%Request.Handle{} = request, opts \\ []) when is_list(opts) do
    timeout = Keyword.get(opts, :timeout, 30_000)

    request
    |> Request.await(timeout: timeout)
    |> then(&finalize_chat_request(request.server, request.id, &1))
    |> Jidoka.Hooks.translate_chat_result()
    |> normalize_chat_result(request.server, opts)
  end

  @doc """
  Returns the current handoff owner for a conversation, if any.
  """
  @spec handoff_owner(String.t()) :: map() | nil
  def handoff_owner(conversation_id), do: Jidoka.Handoff.Registry.owner(conversation_id)

  @doc """
  Clears the current handoff owner for a conversation.
  """
  @spec reset_handoff(String.t()) :: :ok
  def reset_handoff(conversation_id), do: Jidoka.Handoff.Registry.reset(conversation_id)

  defp chat_config(server) do
    case Jido.AgentServer.state(server) do
      {:ok, %{agent_module: runtime_module}} when is_atom(runtime_module) ->
        if function_exported?(runtime_module, :__jidoka_definition__, 0) do
          definition = runtime_module.__jidoka_definition__()

          %{
            context: Map.get(definition, :context, %{}),
            context_schema: Map.get(definition, :context_schema),
            ash: ash_config(definition)
          }
        else
          nil
        end

      _ ->
        nil
    end
  end

  defp ash_config(%{ash_domain: nil}), do: nil

  defp ash_config(%{ash_domain: domain, requires_actor?: require_actor?}) do
    %{domain: domain, require_actor?: require_actor?}
  end

  defp ash_config(_definition), do: nil

  @doc """
  Returns Jidoka's inspection view of an agent definition or running agent.

  Accepted inputs:

  - a compiled Jidoka agent module
  - an imported Jidoka agent struct
  - a dynamic-agent compatibility struct
  - a running agent PID
  - a running agent ID string
  """
  @spec inspect_agent(module() | struct() | pid() | String.t()) :: {:ok, map()} | {:error, term()}
  def inspect_agent(target), do: Jidoka.Inspection.inspect_agent(target)

  @doc """
  Returns Jidoka's inspection view of a compiled workflow definition.
  """
  @spec inspect_workflow(module()) :: {:ok, map()} | {:error, term()}
  def inspect_workflow(workflow_module), do: Jidoka.Inspection.inspect_workflow(workflow_module)

  @doc """
  Returns a summary for the latest request on a running Jidoka agent.
  """
  @spec inspect_request(pid() | String.t() | Jido.Agent.t()) ::
          {:ok, map()} | {:error, term()}
  def inspect_request(target), do: Jidoka.Inspection.inspect_request(target)

  @doc """
  Returns a summary for a specific request on an agent.
  """
  @spec inspect_request(pid() | String.t() | Jido.Agent.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def inspect_request(target, request_id), do: Jidoka.Inspection.inspect_request(target, request_id)

  @doc false
  @spec chat_request(pid() | atom() | {:via, module(), term()}, String.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def chat_request(server, message, opts) when is_binary(message) and is_list(opts) do
    timeout = Keyword.get(opts, :timeout, 30_000)

    request_opts = Keyword.merge(opts, signal_type: "ai.react.query", source: "/jidoka/agent")

    with {:ok, request} <- Request.create_and_send(server, message, request_opts),
         await_result <- Request.await(request, timeout: timeout) do
      finalize_request_result(server, request, await_result)
    end
  end

  defp resolve_server(id, opts) when is_binary(id) do
    case whereis(id, opts) do
      nil -> {:error, :not_found}
      pid -> {:ok, pid}
    end
  end

  defp resolve_server(server, _opts), do: {:ok, server}

  defp validate_conversation_opt(opts) do
    case Keyword.fetch(opts, :conversation) do
      {:ok, conversation_id} when is_binary(conversation_id) ->
        if String.trim(conversation_id) == "" do
          {:error, Jidoka.Error.Normalize.chat_option_error({:invalid_conversation, conversation_id})}
        else
          :ok
        end

      {:ok, conversation_id} ->
        {:error, Jidoka.Error.Normalize.chat_option_error({:invalid_conversation, conversation_id})}

      :error ->
        :ok
    end
  end

  defp route_conversation_owner(default_target, opts) do
    case Keyword.get(opts, :conversation) do
      conversation_id when is_binary(conversation_id) ->
        case Jidoka.Handoff.Registry.owner(conversation_id) do
          %{agent_id: agent_id} when is_binary(agent_id) -> {:ok, agent_id}
          _ -> {:ok, default_target}
        end

      _ ->
        {:ok, default_target}
    end
  end

  defp normalize_chat_result({:error, reason}, target, opts) do
    case Jidoka.Error.Normalize.chat_error(reason,
           target: target,
           timeout: Keyword.get(opts, :timeout, 30_000)
         ) do
      {:handoff, %Jidoka.Handoff{} = handoff} -> {:handoff, handoff}
      error -> {:error, error}
    end
  end

  defp normalize_chat_result({:handoff, %Jidoka.Handoff{} = handoff}, _target, _opts), do: {:handoff, handoff}
  defp normalize_chat_result(result, _target, _opts), do: result

  defp normalize_start_chat_result({:error, reason}, target, opts) do
    {:error,
     Jidoka.Error.Normalize.chat_error(reason,
       target: target,
       timeout: Keyword.get(opts, :timeout, 30_000)
     )}
  end

  defp normalize_start_chat_result(result, _target, _opts), do: result

  @doc false
  @spec finalize_chat_request(pid() | atom() | {:via, module(), term()}, String.t(), term()) ::
          {:ok, term()} | {:error, term()}
  def finalize_chat_request(_server, _request_id, {:error, :timeout} = error), do: error

  def finalize_chat_request(server, request_id, fallback_result) when is_binary(request_id) do
    case Jido.AgentServer.state(server) do
      {:ok, %{agent: agent}} ->
        case Request.get_request(agent, request_id) do
          %{meta: %{jidoka_guardrails: %{interrupt: interrupt}}} ->
            {:error, {:interrupt, interrupt}}

          %{meta: %{jidoka_guardrails: %{error: error}}} ->
            {:error, error}

          %{meta: %{jidoka_hooks: %{interrupt: interrupt}}} ->
            {:error, {:interrupt, interrupt}}

          %{meta: %{jidoka_handoffs: %{calls: [%{outcome: :handoff, handoff: %Jidoka.Handoff{} = handoff} | _]}}} ->
            case Request.get_result(agent, request_id) do
              {:error, {:handoff, %Jidoka.Handoff{} = result_handoff}} ->
                {:error, {:handoff, result_handoff}}

              {:error, {:failed, _status, {:handoff, %Jidoka.Handoff{} = result_handoff}}} ->
                {:error, {:handoff, result_handoff}}

              _ ->
                {:error, {:handoff, handoff}}
            end

          _request ->
            case Request.get_result(agent, request_id) do
              {:pending, _request} -> fallback_result
              nil -> fallback_result
              result -> result
            end
        end

      {:error, _reason} ->
        fallback_result
    end
  end

  defp finalize_request_result(_server, _request, {:error, :timeout} = error), do: error

  defp finalize_request_result(
         server,
         %Request.Handle{id: request_id} = _request,
         fallback_result
       ) do
    finalize_chat_request(server, request_id, fallback_result)
  end

  defp resolve_string_alias(name) when is_binary(name) do
    known_aliases =
      Map.keys(model_aliases()) ++
        Map.keys(Jido.AI.model_aliases())

    case Enum.find(known_aliases, &(Atom.to_string(&1) == name)) do
      nil -> :error
      alias_name -> {:ok, alias_name}
    end
  end
end
