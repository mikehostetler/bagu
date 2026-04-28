defmodule Jidoka.Agent.RequestTransformer do
  @moduledoc false

  alias Jido.AI.Reasoning.ReAct.{Config, State}

  @spec transform_request(
          Jidoka.Agent.SystemPrompt.spec() | nil,
          Jidoka.Character.spec(),
          Jidoka.Skill.config() | nil,
          map(),
          State.t(),
          Config.t(),
          map()
        ) :: {:ok, %{messages: [map()]}} | {:error, term()}
  def transform_request(
        system_prompt_spec,
        character_spec,
        skills_config,
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
         {:ok, character_prompt} <- resolve_character_prompt(character_spec, input, runtime_context),
         combined <- combine_prompt_sections(character_prompt, prompt, skills_config, runtime_context) do
      Jidoka.Debug.record_prompt_preview(runtime_context, combined, request)
      {:ok, %{messages: apply_prompt(Map.get(request, :messages, []), combined)}}
    end
  end

  @spec transform_request(
          Jidoka.Agent.SystemPrompt.spec() | nil,
          Jidoka.Skill.config() | nil,
          map(),
          State.t(),
          Config.t(),
          map()
        ) :: {:ok, %{messages: [map()]}} | {:error, term()}
  def transform_request(system_prompt_spec, skills_config, request, state, config, runtime_context) do
    transform_request(system_prompt_spec, nil, skills_config, request, state, config, runtime_context)
  end

  defp resolve_base_prompt(nil, %{request: request}),
    do: {:ok, Jidoka.Agent.SystemPrompt.extract_system_prompt(request.messages)}

  defp resolve_base_prompt(spec, input), do: Jidoka.Agent.SystemPrompt.resolve(spec, input)

  defp resolve_character_prompt(character_spec, input, runtime_context) do
    runtime_context
    |> Jidoka.Character.runtime_override()
    |> case do
      nil -> character_spec
      override -> override
    end
    |> Jidoka.Character.resolve(input)
  end

  defp combine_prompt_sections(character_prompt, prompt, skills_config, runtime_context) do
    sections =
      [
        normalize_prompt(character_prompt),
        normalize_prompt(prompt),
        skills_prompt(skills_config, runtime_context),
        Jidoka.Memory.prompt_text(runtime_context),
        Jidoka.Output.instructions(runtime_context)
      ]
      |> Enum.reject(&is_nil/1)

    Enum.join(sections, "\n\n")
  end

  defp skills_prompt(nil, runtime_context), do: Jidoka.Skill.prompt_text(runtime_context)
  defp skills_prompt(_config, runtime_context), do: Jidoka.Skill.prompt_text(runtime_context)

  defp apply_prompt(messages, ""), do: messages

  defp apply_prompt(messages, prompt),
    do: Jidoka.Agent.SystemPrompt.put_system_prompt(messages, prompt)

  defp normalize_prompt(nil), do: nil
  defp normalize_prompt(prompt) when is_binary(prompt) and prompt == "", do: nil
  defp normalize_prompt(prompt) when is_binary(prompt), do: prompt
end
