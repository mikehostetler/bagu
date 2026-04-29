defmodule Jidoka do
  @moduledoc """
  Minimal runtime facade for starting and discovering Jidoka agents.
  """

  alias Jidoka.ImportedAgent

  @doc """
  Returns Jidoka-owned model aliases from application config.

  These aliases are defined under `config :jidoka, :model_aliases`.
  """
  @spec model_aliases() :: %{optional(atom()) => term()}
  defdelegate model_aliases(), to: Jidoka.Model

  @doc """
  Normalizes a model input using Jidoka aliases first, then Jido.AI.
  """
  @spec model(Jido.AI.model_input()) :: ReqLLM.model_input()
  defdelegate model(model), to: Jidoka.Model

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
  defdelegate chat(server_or_id, message, opts \\ []), to: Jidoka.Chat

  @doc false
  @spec start_chat_request(pid() | atom() | {:via, module(), term()} | String.t(), String.t(), keyword()) ::
          {:ok, Jido.AI.Request.Handle.t()} | {:error, term()}
  defdelegate start_chat_request(server_or_id, message, opts \\ []), to: Jidoka.Chat

  @doc false
  @spec await_chat_request(Jido.AI.Request.Handle.t(), keyword()) ::
          {:ok, term()} | {:error, term()} | {:interrupt, Jidoka.Interrupt.t()} | {:handoff, Jidoka.Handoff.t()}
  defdelegate await_chat_request(request, opts \\ []), to: Jidoka.Chat

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

  @doc """
  Returns the latest structured runtime trace for a running Jidoka agent.
  """
  @spec inspect_trace(pid() | String.t() | Jido.Agent.t()) ::
          {:ok, Jidoka.Trace.t()} | {:error, term()}
  def inspect_trace(target), do: Jidoka.Trace.latest(target)

  @doc """
  Returns the structured runtime trace for a specific request.
  """
  @spec inspect_trace(pid() | String.t() | Jido.Agent.t(), String.t()) ::
          {:ok, Jidoka.Trace.t()} | {:error, term()}
  def inspect_trace(target, request_id), do: Jidoka.Trace.for_request(target, request_id)

  @doc false
  @spec chat_request(pid() | atom() | {:via, module(), term()}, String.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  defdelegate chat_request(server, message, opts), to: Jidoka.Chat

  @doc false
  @spec finalize_chat_request(pid() | atom() | {:via, module(), term()}, String.t(), term()) ::
          {:ok, term()} | {:error, term()}
  defdelegate finalize_chat_request(server, request_id, fallback_result), to: Jidoka.Chat
end
