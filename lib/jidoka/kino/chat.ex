defmodule Jidoka.Kino.Chat do
  @moduledoc false

  alias Jidoka.Kino.{LogTrace, Render, RuntimeSetup}

  @spec chat(String.t(), (-> term()), keyword()) :: term()
  def chat(label, fun, opts \\ []) when is_binary(label) and is_function(fun, 0) do
    with {:ok, _source} <-
           RuntimeSetup.load_provider_env(Keyword.get(opts, :provider_env, RuntimeSetup.provider_env_names())) do
      result =
        label
        |> LogTrace.trace(fun, opts)
        |> format_chat_result()

      if Keyword.get(opts, :render_result?, true) do
        render_chat_result(label, result)
      end

      result
    end
  end

  @spec format_chat_result(term()) :: term()
  def format_chat_result({:ok, turn}), do: {:ok, extract_turn_text(turn)}
  def format_chat_result({:handoff, %Jidoka.Handoff{} = handoff}), do: {:handoff, handoff_summary(handoff)}
  def format_chat_result({:interrupt, %Jidoka.Interrupt{} = interrupt}), do: {:interrupt, interrupt_summary(interrupt)}
  def format_chat_result({:error, {:handoff, %Jidoka.Handoff{} = handoff}}), do: {:handoff, handoff_summary(handoff)}

  def format_chat_result({:error, {:interrupt, %Jidoka.Interrupt{} = interrupt}}),
    do: {:interrupt, interrupt_summary(interrupt)}

  def format_chat_result({:error, reason}), do: {:error, Jidoka.Error.format(reason)}
  def format_chat_result(other), do: other

  defp render_chat_result(label, result) do
    Render.table("Turn result: #{label}", [chat_result_row(result)], keys: [:status, :summary])
  end

  defp chat_result_row({:ok, text}), do: %{status: "ok", summary: Render.inspect_value(text, 50)}

  defp chat_result_row({:handoff, summary}) when is_map(summary) do
    %{
      status: "handoff",
      summary:
        [
          "to=#{Map.get(summary, :to_agent_id)}",
          "conversation=#{Map.get(summary, :conversation_id)}",
          Map.get(summary, :reason)
        ]
        |> Enum.reject(&Render.blank?/1)
        |> Enum.join(", ")
    }
  end

  defp chat_result_row({:interrupt, summary}) when is_map(summary) do
    %{status: "interrupt", summary: "#{Map.get(summary, :kind)}: #{Map.get(summary, :message)}"}
  end

  defp chat_result_row({:error, message}), do: %{status: "error", summary: to_string(message)}
  defp chat_result_row(other), do: %{status: "result", summary: Render.inspect_value(other, 50)}

  defp extract_turn_text(text) when is_binary(text), do: text

  defp extract_turn_text(turn) do
    Jido.AI.Turn.extract_text(turn)
  rescue
    _error -> turn
  end

  defp handoff_summary(%Jidoka.Handoff{} = handoff) do
    %{
      id: handoff.id,
      name: handoff.name,
      conversation_id: handoff.conversation_id,
      from_agent: handoff.from_agent,
      to_agent: handoff.to_agent,
      to_agent_id: handoff.to_agent_id,
      message: handoff.message,
      summary: handoff.summary,
      reason: handoff.reason,
      context_keys: handoff.context |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort(),
      request_id: handoff.request_id
    }
  end

  defp interrupt_summary(%Jidoka.Interrupt{} = interrupt) do
    %{
      id: interrupt.id,
      kind: interrupt.kind,
      message: interrupt.message,
      data_keys: interrupt.data |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort(),
      data: interrupt.data
    }
  end
end
