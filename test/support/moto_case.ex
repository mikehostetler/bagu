defmodule MotoTest.Support.Case do
  use ExUnit.CaseTemplate

  using opts do
    async = Keyword.get(opts, :async, false)

    quote do
      use ExUnit.Case, async: unquote(async)

      import ExUnit.CaptureLog
      import MotoTest.Support.Helpers

      alias Moto.DynamicAgent
      alias MotoTest.Support.{Accounts, AshResourceAgent, User}
    end
  end
end

defmodule MotoTest.Support.Helpers do
  alias Jido.AI.Reasoning.ReAct.{Config, State}

  def react_request(messages) when is_list(messages) do
    %{messages: messages, llm_opts: [], tools: %{}}
  end

  def react_state do
    State.new("hello", nil, request_id: "req-test", run_id: "run-test")
  end

  def react_config(request_transformer) do
    Config.new(
      model: :fast,
      system_prompt: nil,
      request_transformer: request_transformer,
      streaming: false
    )
  end

  def new_runtime_agent(module) do
    module.new(id: "agent-#{System.unique_integer([:positive])}")
  end

  def find_tool(agent_module, name) do
    Enum.find(agent_module.tools(), fn tool_module ->
      tool_module.name() == name
    end)
  end
end
