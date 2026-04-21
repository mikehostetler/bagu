defmodule MotoTest.ChatAgent do
  use Moto.Agent

  agent do
    model(:fast)
    system_prompt("You are a concise assistant.")
  end
end

defmodule MotoTest.ContextAgent do
  use Moto.Agent

  agent do
    model(:fast)
    system_prompt("You are a context-aware assistant.")

    schema(
      Zoi.object(%{
        tenant: Zoi.string() |> Zoi.default("demo"),
        channel: Zoi.string() |> Zoi.default("test"),
        session: Zoi.string() |> Zoi.optional()
      })
    )
  end
end

defmodule MotoTest.StringModelAgent do
  use Moto.Agent

  agent do
    model("openai:gpt-4.1")
    system_prompt("You are a concise assistant.")
  end
end

defmodule MotoTest.TenantPrompt do
  @behaviour Moto.Agent.SystemPrompt

  @impl true
  def resolve_system_prompt(%{context: context}) do
    tenant = Map.get(context, :tenant, Map.get(context, "tenant", "unknown"))
    "You are helping tenant #{tenant}."
  end
end

defmodule MotoTest.PromptCallbacks do
  def build(%{context: context}, prefix) do
    tenant = Map.get(context, :tenant, Map.get(context, "tenant", "unknown"))
    {:ok, "#{prefix} #{tenant}."}
  end
end

defmodule MotoTest.ModulePromptAgent do
  use Moto.Agent

  agent do
    model(:fast)
    system_prompt(MotoTest.TenantPrompt)
  end
end

defmodule MotoTest.MfaPromptAgent do
  use Moto.Agent

  agent do
    model(:fast)
    system_prompt({MotoTest.PromptCallbacks, :build, ["Serve tenant"]})
  end
end

defmodule MotoTest.InlineMapModelAgent do
  use Moto.Agent

  agent do
    model(%{provider: :openai, id: "gpt-4.1", base_url: "http://localhost:4000/v1"})
    system_prompt("You are a concise assistant.")
  end
end

defmodule MotoTest.StructModelAgent do
  use Moto.Agent

  agent do
    model(%LLMDB.Model{provider: :openai, id: "gpt-4.1"})
    system_prompt("You are a concise assistant.")
  end
end
