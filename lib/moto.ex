defmodule Moto do
  @moduledoc """
  Minimal runtime facade for starting and discovering Moto agents.
  """

  alias Jido.AI.Request
  alias Moto.DynamicAgent

  @doc """
  Returns Moto-owned model aliases from application config.

  These aliases are defined under `config :moto, :model_aliases`.
  """
  @spec model_aliases() :: %{optional(atom()) => term()}
  def model_aliases do
    case Application.get_env(:moto, :model_aliases, %{}) do
      aliases when is_map(aliases) -> aliases
      _ -> %{}
    end
  end

  @doc """
  Normalizes a model input using Moto aliases first, then Jido.AI.
  """
  @spec model(Jido.AI.model_input()) :: ReqLLM.model_input()
  def model(model) when is_atom(model) do
    case model_aliases() do
      %{^model => resolved} -> resolved
      _ -> Jido.AI.resolve_model(model)
    end
  end

  def model(model), do: Jido.AI.resolve_model(model)

  @doc """
  Starts an agent under the shared `Moto.Runtime` instance.
  """
  def start_agent(agent, opts \\ [])

  @spec start_agent(DynamicAgent.t(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_agent(%DynamicAgent{} = agent, opts), do: DynamicAgent.start_link(agent, opts)

  @spec start_agent(module() | struct(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_agent(agent, opts), do: Moto.Runtime.start_agent(agent, opts)

  @doc """
  Stops an agent by PID or registered ID.
  """
  @spec stop_agent(pid() | String.t(), keyword()) :: :ok | {:error, :not_found}
  def stop_agent(pid_or_id, opts \\ []), do: Moto.Runtime.stop_agent(pid_or_id, opts)

  @doc """
  Looks up a running agent by ID.
  """
  @spec whereis(String.t(), keyword()) :: pid() | nil
  def whereis(id, opts \\ []), do: Moto.Runtime.whereis(id, opts)

  @doc """
  Lists all running agents.
  """
  @spec list_agents(keyword()) :: [{String.t(), pid()}]
  def list_agents(opts \\ []), do: Moto.Runtime.list_agents(opts)

  @doc """
  Imports a constrained dynamic Moto agent from a map, JSON string, or YAML string.

  The imported format currently supports `name`, `model`, `system_prompt`,
  published tool names via `tools`, published plugin names via `plugins`,
  and published hook names via `hooks`.

  Imported tools and plugins must be resolved through the explicit
  `:available_tools`, `:available_plugins`, and `:available_hooks` registries
  passed in `opts`.
  """
  @spec import_agent(map() | binary(), keyword()) :: {:ok, DynamicAgent.t()} | {:error, term()}
  def import_agent(source, opts \\ []), do: DynamicAgent.import(source, opts)

  @doc """
  Imports a constrained dynamic Moto agent and raises on failure.
  """
  @spec import_agent!(map() | binary(), keyword()) :: DynamicAgent.t()
  def import_agent!(source, opts \\ []) do
    case import_agent(source, opts) do
      {:ok, agent} -> agent
      {:error, reason} -> raise ArgumentError, message: DynamicAgent.format_error(reason)
    end
  end

  @doc """
  Imports a constrained dynamic Moto agent from a `.json`, `.yaml`, or `.yml` file.
  """
  @spec import_agent_file(Path.t(), keyword()) :: {:ok, DynamicAgent.t()} | {:error, term()}
  def import_agent_file(path, opts \\ []), do: DynamicAgent.import_file(path, opts)

  @doc """
  Imports a constrained dynamic Moto agent from a file and raises on failure.
  """
  @spec import_agent_file!(Path.t(), keyword()) :: DynamicAgent.t()
  def import_agent_file!(path, opts \\ []) do
    case import_agent_file(path, opts) do
      {:ok, agent} -> agent
      {:error, reason} -> raise ArgumentError, message: DynamicAgent.format_error(reason)
    end
  end

  @doc """
  Encodes an imported Moto agent as JSON or YAML.
  """
  @spec encode_agent(DynamicAgent.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def encode_agent(%DynamicAgent{} = agent, opts \\ []), do: DynamicAgent.encode(agent, opts)

  @doc """
  Encodes an imported Moto agent as JSON or YAML and raises on failure.
  """
  @spec encode_agent!(DynamicAgent.t(), keyword()) :: binary()
  def encode_agent!(%DynamicAgent{} = agent, opts \\ []) do
    case encode_agent(agent, opts) do
      {:ok, encoded} -> encoded
      {:error, reason} -> raise ArgumentError, message: DynamicAgent.format_error(reason)
    end
  end

  @doc """
  Sends a chat request to a running Moto agent and waits for the result.

  Accepts a PID, server reference, or Moto agent ID string.
  """
  @spec chat(pid() | atom() | {:via, module(), term()} | String.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, term()} | {:interrupt, Moto.Interrupt.t()}
  def chat(server_or_id, message, opts \\ []) when is_binary(message) do
    with {:ok, server} <- resolve_server(server_or_id, opts),
         {:ok, prepared_opts} <- Moto.Agent.prepare_chat_opts(opts, nil) do
      chat_request(server, message, prepared_opts)
      |> Moto.Hooks.translate_chat_result()
    end
  end

  @doc false
  @spec chat_request(pid() | atom() | {:via, module(), term()}, String.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def chat_request(server, message, opts) when is_binary(message) and is_list(opts) do
    timeout = Keyword.get(opts, :timeout, 30_000)

    request_opts = Keyword.merge(opts, signal_type: "ai.react.query", source: "/moto/agent")

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

  defp finalize_request_result(_server, _request, {:error, :timeout} = error), do: error

  defp finalize_request_result(
         server,
         %Request.Handle{id: request_id} = _request,
         fallback_result
       ) do
    case Jido.AgentServer.state(server) do
      {:ok, %{agent: agent}} ->
        case Request.get_request(agent, request_id) do
          %{meta: %{moto_hooks: %{interrupt: interrupt}}} ->
            {:error, {:interrupt, interrupt}}

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
end
