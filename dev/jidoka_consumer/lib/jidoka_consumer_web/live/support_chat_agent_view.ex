defmodule JidokaConsumerWeb.SupportChatAgentView do
  @moduledoc """
  AgentView adapter for the consumer-owned support router agent.

  The Jidoka agent owns execution and `Jido.Thread` owns the canonical event
  log. The LiveView owns rendering and browser events. This module owns the
  least-common-denominator application surface between them: which agent backs
  the session, how conversation/runtime context are derived, and how the agent
  is projected into UI-safe data.
  """

  use Jidoka.AgentView

  alias JidokaConsumer.Support.DemoData

  @agent JidokaConsumer.Support.Agents.SupportRouterAgent

  @impl Jidoka.AgentView
  def prepare(_session) do
    case Code.ensure_compiled(@agent) do
      {:module, @agent} ->
        :ok

      {:error, reason} ->
        {:error,
         Jidoka.Error.config_error("Could not load the consumer support router agent.",
           field: :agent,
           value: @agent,
           details: %{reason: reason}
         )}
    end
  end

  @impl Jidoka.AgentView
  def agent_module(_session), do: @agent

  @impl Jidoka.AgentView
  def conversation_id(session) do
    session
    |> Map.get("conversation_id", "demo")
    |> Jidoka.AgentView.normalize_id("demo")
  end

  @impl Jidoka.AgentView
  def agent_id(session), do: "consumer-support-liveview-" <> conversation_id(session)

  @impl Jidoka.AgentView
  def runtime_context(session) do
    DemoData.context_defaults()
    |> Map.merge(%{
      channel: "phoenix_live_view",
      session: conversation_id(session),
      actor: support_actor(session)
    })
    |> optional_context(session, "account_id", :account_id)
    |> optional_context(session, "account_id", :customer_id)
    |> optional_context(session, "order_id", :order_id)
  end

  defp support_actor(session) do
    %{
      id: session |> Map.get("support_actor_id", "live_view_support_agent") |> to_string(),
      name: session |> Map.get("support_actor_name", "LiveView Support Agent") |> to_string()
    }
  end

  defp optional_context(context, session, session_key, context_key) do
    case Map.get(session, session_key) do
      value when is_binary(value) and value != "" -> Map.put(context, context_key, value)
      _ -> context
    end
  end
end
