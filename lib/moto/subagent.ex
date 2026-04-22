defmodule Moto.Subagent do
  @moduledoc false

  alias Moto.Subagent.{Definition, Runtime, Tool}

  @enforce_keys [:agent, :name, :description, :target, :timeout, :forward_context, :result]
  defstruct [:agent, :name, :description, :target, :timeout, :forward_context, :result]

  @type name :: String.t()
  @type target :: :ephemeral | {:peer, String.t()} | {:peer, {:context, atom() | String.t()}}
  @type forward_context ::
          :public | :none | {:only, [atom() | String.t()]} | {:except, [atom() | String.t()]}
  @type result_mode :: :text | :structured
  @type registry :: %{required(name()) => module()}
  @type t :: %__MODULE__{
          agent: module(),
          name: name(),
          description: String.t(),
          target: target(),
          timeout: pos_integer(),
          forward_context: forward_context(),
          result: result_mode()
        }

  @request_id_key :__moto_request_id__
  @server_key :__moto_server__
  @depth_key :__moto_subagent_depth__

  @spec task_schema() :: Zoi.schema()
  defdelegate task_schema, to: Tool

  @spec output_schema(t()) :: Zoi.schema()
  defdelegate output_schema(subagent), to: Tool

  @spec request_id_key() :: atom()
  def request_id_key, do: @request_id_key

  @spec server_key() :: atom()
  def server_key, do: @server_key

  @spec depth_key() :: atom()
  def depth_key, do: @depth_key

  @spec validate_agent_module(module()) :: :ok | {:error, String.t()}
  defdelegate validate_agent_module(module), to: Definition

  @spec agent_name(module()) :: {:ok, name()} | {:error, String.t()}
  defdelegate agent_name(module), to: Definition

  @spec subagent_names([t()]) :: {:ok, [name()]} | {:error, String.t()}
  defdelegate subagent_names(subagents), to: Definition

  @spec new(module(), keyword()) :: {:ok, t()} | {:error, String.t()}
  defdelegate new(agent_module, opts \\ []), to: Definition

  @spec normalize_available_subagents([module()] | %{required(name()) => module()}) ::
          {:ok, registry()} | {:error, String.t()}
  defdelegate normalize_available_subagents(subagents), to: Definition

  @spec resolve_subagent_name(name(), registry()) :: {:ok, module()} | {:error, String.t()}
  defdelegate resolve_subagent_name(name, registry), to: Definition

  @spec normalize_target(term()) :: {:ok, target()} | {:error, String.t()}
  defdelegate normalize_target(target), to: Definition

  @spec normalize_timeout(term()) :: {:ok, pos_integer()} | {:error, String.t()}
  defdelegate normalize_timeout(timeout), to: Definition

  @spec normalize_forward_context(term()) :: {:ok, forward_context()} | {:error, String.t()}
  defdelegate normalize_forward_context(forward_context), to: Definition

  @spec normalize_result(term()) :: {:ok, result_mode()} | {:error, String.t()}
  defdelegate normalize_result(result), to: Definition

  @spec tool_module(base_module :: module(), t(), non_neg_integer()) :: module()
  defdelegate tool_module(base_module, subagent, index), to: Tool

  @spec tool_module_ast(module(), t()) :: Macro.t()
  defdelegate tool_module_ast(tool_module, subagent), to: Tool

  @spec on_before_cmd(Jido.Agent.t(), term()) :: {:ok, Jido.Agent.t(), term()}
  defdelegate on_before_cmd(agent, action), to: Runtime

  @spec on_after_cmd(Jido.Agent.t(), term(), [term()]) :: {:ok, Jido.Agent.t(), [term()]}
  defdelegate on_after_cmd(agent, action, directives), to: Runtime

  @spec run_subagent_tool(t(), map(), map()) :: {:ok, map()} | {:error, term()}
  defdelegate run_subagent_tool(subagent, params, context), to: Runtime

  @spec run_subagent(t(), map(), map()) :: {:ok, String.t()} | {:error, term()}
  defdelegate run_subagent(subagent, params, context), to: Runtime

  @spec get_request_meta(Jido.Agent.t(), String.t()) :: map() | nil
  defdelegate get_request_meta(agent, request_id), to: Runtime

  @doc """
  Returns the recorded subagent calls for a request.

  This prefers persisted request metadata when available, and falls back to the
  transient ETS buffer used during live ReAct runs.
  """
  @spec request_calls(pid() | String.t() | Jido.Agent.t(), String.t()) :: [map()]
  defdelegate request_calls(server_or_agent, request_id), to: Runtime

  @doc """
  Returns the recorded subagent calls for the latest request on a running agent.
  """
  @spec latest_request_calls(pid() | String.t()) :: [map()]
  defdelegate latest_request_calls(server_or_id), to: Runtime
end
