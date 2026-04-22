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
    id :skill_agent
  end

  defaults do
    model :fast
    instructions "You can use skills."
  end

  capabilities do
    skill MotoTest.ModuleMathSkill
  end
end

defmodule MotoTest.RuntimeSkillAgent do
  use Moto.Agent

  agent do
    id :runtime_skill_agent
  end

  defaults do
    model :fast
    instructions "You can use runtime skills."
  end

  capabilities do
    skill "math-discipline"
    load_path "../fixtures/skills"
  end
end

defmodule MotoTest.MCPAgent do
  use Moto.Agent

  agent do
    id :mcp_agent
  end

  defaults do
    model :fast
    instructions "You can use MCP-synced tools."
  end

  capabilities do
    mcp_tools endpoint: :github, prefix: "github_"
  end
end

defmodule MotoTest.LocalFSMCPAgent do
  use Moto.Agent

  agent do
    id :local_fsmcp_agent
  end

  defaults do
    model :fast
    instructions "You can use filesystem MCP tools."
  end

  capabilities do
    mcp_tools endpoint: :local_fs, prefix: "fs_"
  end
end

defmodule MotoTest.InlineMCPAgent do
  use Moto.Agent

  agent do
    id :inline_mcp_agent
  end

  defaults do
    model :fast
    instructions "You can use an inline MCP endpoint."
  end

  capabilities do
    mcp_tools endpoint: :inline_fs,
              prefix: "inline_",
              transport: {:stdio, command: "echo"},
              client_info: %{name: "moto-test", version: "0.1.0"},
              timeouts: %{request_ms: 15_000}
  end
end

defmodule MotoTest.FakeMCPSync do
  def run(params, _context) do
    send(self(), {:mcp_sync_called, params})
    {:ok, %{registered_count: 1}}
  end
end

defmodule MotoTest.FailingMCPSync do
  def run(params, _context) do
    send(self(), {:mcp_sync_called, params})
    {:error, :server_capabilities_not_set}
  end
end
