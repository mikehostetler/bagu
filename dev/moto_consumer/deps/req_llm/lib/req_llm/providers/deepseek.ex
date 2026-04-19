defmodule ReqLLM.Providers.Deepseek do
  @moduledoc """
  DeepSeek AI provider – OpenAI-compatible Chat Completions API.

  ## Implementation

  Uses built-in OpenAI-style encoding/decoding defaults.
  DeepSeek is fully OpenAI-compatible, so no custom request/response handling is needed.

  ## Authentication

  Requires a DeepSeek API key from https://platform.deepseek.com/

  ## Configuration

      # Add to .env file (automatically loaded)
      DEEPSEEK_API_KEY=your-api-key

  ## Examples

      # Basic usage
      ReqLLM.generate_text("deepseek:deepseek-chat", "Hello!")

      # With custom parameters
      ReqLLM.generate_text("deepseek:deepseek-reasoner", "Write a function",
        temperature: 0.2,
        max_tokens: 2000
      )

      # Streaming
      ReqLLM.stream_text("deepseek:deepseek-chat", "Tell me a story")
      |> Enum.each(&IO.write/1)

  ## Models

  DeepSeek offers several models including:

  - `deepseek-chat` - General purpose conversational model
  - `deepseek-reasoner` - Reasoning and problem-solving

  See https://platform.deepseek.com/docs for full model documentation.
  """

  use ReqLLM.Provider,
    id: :deepseek,
    default_base_url: "https://api.deepseek.com",
    default_env_key: "DEEPSEEK_API_KEY"

  use ReqLLM.Provider.Defaults

  @provider_schema []
end
