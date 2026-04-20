defmodule Moto.Agent.RequestTransformer do
  @moduledoc false

  alias Jido.AI.Reasoning.ReAct.{Config, State}

  @spec transform_request(
          Moto.Agent.SystemPrompt.spec() | nil,
          map(),
          State.t(),
          Config.t(),
          map()
        ) :: {:ok, %{messages: [map()]}} | {:error, term()}
  def transform_request(
        system_prompt_spec,
        request,
        %State{} = state,
        %Config{} = config,
        runtime_context
      )
      when is_map(request) and is_map(runtime_context) do
    input = %{
      request: request,
      state: state,
      config: config,
      context: runtime_context
    }

    with {:ok, prompt} <- resolve_base_prompt(system_prompt_spec, input),
         combined <- maybe_append_memory(prompt, runtime_context) do
      {:ok, %{messages: apply_prompt(Map.get(request, :messages, []), combined)}}
    end
  end

  defp resolve_base_prompt(nil, %{request: request}),
    do: {:ok, Moto.Agent.SystemPrompt.extract_system_prompt(request.messages)}

  defp resolve_base_prompt(spec, input), do: Moto.Agent.SystemPrompt.resolve(spec, input)

  defp maybe_append_memory(prompt, runtime_context) do
    sections =
      [normalize_prompt(prompt), Moto.Memory.prompt_text(runtime_context)]
      |> Enum.reject(&is_nil/1)

    Enum.join(sections, "\n\n")
  end

  defp apply_prompt(messages, ""), do: messages

  defp apply_prompt(messages, prompt),
    do: Moto.Agent.SystemPrompt.put_system_prompt(messages, prompt)

  defp normalize_prompt(nil), do: nil
  defp normalize_prompt(prompt) when is_binary(prompt) and prompt == "", do: nil
  defp normalize_prompt(prompt) when is_binary(prompt), do: prompt
end
