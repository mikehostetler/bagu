defmodule MotoTest.ModuleMathSkill do
  use Jido.AI.Skill,
    name: "module-math-skill",
    description: "Provides multiply_numbers and enforces a calculation workflow.",
    allowed_tools: ["multiply_numbers"],
    actions: [MotoTest.MultiplyNumbers],
    body: """
    # Module Math Skill

    Use the multiply_numbers tool whenever multiplication is required.
    Keep the response short.
    """
end

defmodule MotoTest.SkillAgent do
  use Moto.Agent

  agent do
    model(:fast)
    system_prompt("You can use skills.")
  end

  skills do
    skill(MotoTest.ModuleMathSkill)
  end
end

defmodule MotoTest.RuntimeSkillAgent do
  use Moto.Agent

  agent do
    model(:fast)
    system_prompt("You can use runtime skills.")
  end

  skills do
    skill("math-discipline")
    load_path("../fixtures/skills")
  end
end

defmodule MotoTest.MCPAgent do
  use Moto.Agent

  agent do
    model(:fast)
    system_prompt("You can use MCP-synced tools.")
  end

  tools do
    mcp_tools(endpoint: :github, prefix: "github_")
  end
end

defmodule MotoTest.FakeMCPSync do
  def run(params, _context) do
    send(self(), {:mcp_sync_called, params})
    {:ok, %{registered_count: 1}}
  end
end
