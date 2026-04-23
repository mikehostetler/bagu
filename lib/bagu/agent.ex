defmodule Bagu.Agent do
  @moduledoc """
  Thin Spark-backed wrapper around `Jido.AI.Agent` for Bagu.

  This first DSL is intentionally tiny:

      defmodule MyApp.ChatAgent do
        use Bagu.Agent

        agent do
          id :chat_agent
          schema Zoi.object(%{tenant: Zoi.string() |> Zoi.optional()})
        end

        defaults do
          model :fast
          instructions "You are a concise assistant."
        end

        capabilities do
          tool MyApp.Tools.AddNumbers
          ash_resource MyApp.Accounts.User
        end
      end

  Supported fields are intentionally limited:

  - `agent.id`
  - `agent.schema` as an optional Zoi map/object schema for runtime context
  - `defaults.model`
  - `defaults.instructions` as a string, module callback, or MFA tuple
  - `capabilities` for tools, Ash resources, MCP tools, skills, plugins, subagents, and workflows
  - `lifecycle` for memory, hooks, and guardrails

  A nested runtime module is generated automatically and uses `Jido.AI.Agent`
  with the configured tool modules. The `capabilities` block currently supports
  explicit `Bagu.Tool` modules and `ash_resource` expansion via `AshJido`.
  Subagent entries compile specialist agents into tool-like delegation
  capabilities while keeping the parent agent in control. Subagent entries can
  tune child `timeout`, public `forward_context`, and parent-visible `result`
  shape without introducing handoffs or workflow graphs.
  Workflow entries compile deterministic `Bagu.Workflow` modules into
  tool-like capabilities while keeping ordered business processes in the
  workflow runtime.
  Plugin entries accept `Bagu.Plugin` modules and merge their declared
  action-backed tools into the same LLM-visible tool registry.
  """

  @doc false
  @spec prepare_chat_opts(keyword(), map() | nil) :: {:ok, keyword()} | {:error, term()}
  def prepare_chat_opts(opts, config \\ nil) when is_list(opts) do
    Bagu.Agent.Chat.prepare_chat_opts(opts, config)
  end

  defmacro __using__(opts \\ []) do
    if opts != [] do
      raise CompileError,
        file: __CALLER__.file,
        line: __CALLER__.line,
        description: "Bagu.Agent now uses a Spark DSL. Use `use Bagu.Agent` and configure it inside `agent do ... end`."
    end

    quote location: :keep do
      use Bagu.Agent.SparkDsl

      @before_compile Bagu.Agent
    end
  end

  defmacro __before_compile__(env) do
    Bagu.Agent.Build.before_compile(env)
  end
end
