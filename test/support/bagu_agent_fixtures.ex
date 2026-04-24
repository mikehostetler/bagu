defmodule BaguTest.ChatAgent do
  use Bagu.Agent

  agent do
    id :chat_agent
  end

  defaults do
    model :fast
    instructions "You are a concise assistant."
  end
end

defmodule BaguTest.ContextAgent do
  use Bagu.Agent

  @context_fields %{
    tenant: Zoi.string() |> Zoi.default("demo"),
    channel: Zoi.string() |> Zoi.default("test"),
    session: Zoi.string() |> Zoi.optional()
  }

  agent do
    id :context_agent

    schema Zoi.object(@context_fields)
  end

  defaults do
    model :fast
    instructions "You are a context-aware assistant."
  end
end

defmodule BaguTest.RequiredContextAgent do
  use Bagu.Agent

  @context_fields %{
    account_id: Zoi.string(),
    tenant: Zoi.string() |> Zoi.default("demo")
  }

  agent do
    id :required_context_agent

    schema Zoi.object(@context_fields)
  end

  defaults do
    model :fast
    instructions "You require account context."
  end
end

defmodule BaguTest.StringModelAgent do
  use Bagu.Agent

  agent do
    id :string_model_agent
  end

  defaults do
    model "openai:gpt-4.1"
    instructions "You are a concise assistant."
  end
end

defmodule BaguTest.TenantPrompt do
  @behaviour Bagu.Agent.SystemPrompt

  @impl true
  def resolve_system_prompt(%{context: context}) do
    tenant = Map.get(context, :tenant, Map.get(context, "tenant", "unknown"))
    "You are helping tenant #{tenant}."
  end
end

defmodule BaguTest.PromptCallbacks do
  def build(%{context: context}, prefix) do
    tenant = Map.get(context, :tenant, Map.get(context, "tenant", "unknown"))
    {:ok, "#{prefix} #{tenant}."}
  end
end

defmodule BaguTest.SupportCharacter do
  use Jido.Character,
    defaults: %{
      name: "Support Advisor",
      identity: %{role: "Support specialist"},
      voice: %{tone: :professional, style: "Practical and concise"},
      instructions: ["Use the configured support persona."]
    }
end

defmodule BaguTest.ModulePromptAgent do
  use Bagu.Agent

  agent do
    id :module_prompt_agent
  end

  defaults do
    model :fast
    instructions BaguTest.TenantPrompt
  end
end

defmodule BaguTest.MfaPromptAgent do
  use Bagu.Agent

  agent do
    id :mfa_prompt_agent
  end

  defaults do
    model :fast
    instructions {BaguTest.PromptCallbacks, :build, ["Serve tenant"]}
  end
end

defmodule BaguTest.CharacterAgent do
  use Bagu.Agent

  agent do
    id :character_agent
  end

  defaults do
    model :fast

    character(%{
      name: "Policy Advisor",
      identity: %{role: "Support policy specialist"},
      voice: %{tone: :professional, style: "Clear and direct"},
      instructions: ["Stay within published policy."]
    })

    instructions "Answer with the support policy first."
  end
end

defmodule BaguTest.ModuleCharacterAgent do
  use Bagu.Agent

  agent do
    id :module_character_agent
  end

  defaults do
    model :fast
    character(BaguTest.SupportCharacter)
    instructions "Adapt the response to the account tier."
  end
end

defmodule BaguTest.InlineMapModelAgent do
  use Bagu.Agent

  agent do
    id :inline_map_model_agent
  end

  defaults do
    model %{provider: :openai, id: "gpt-4.1", base_url: "http://localhost:4000/v1"}
    instructions "You are a concise assistant."
  end
end

defmodule BaguTest.StructModelAgent do
  use Bagu.Agent

  agent do
    id :struct_model_agent
  end

  defaults do
    model %LLMDB.Model{provider: :openai, id: "gpt-4.1"}
    instructions "You are a concise assistant."
  end
end
