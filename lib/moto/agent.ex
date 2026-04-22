defmodule Moto.Agent do
  @moduledoc """
  Thin Spark-backed wrapper around `Jido.AI.Agent` for Moto.

  This first DSL is intentionally tiny:

      defmodule MyApp.ChatAgent do
        use Moto.Agent

        agent do
          name "chat_agent"
          model :fast
          system_prompt "You are a concise assistant."
          schema Zoi.object(%{tenant: Zoi.string() |> Zoi.optional()})
        end

        tools do
          tool MyApp.Tools.AddNumbers
          ash_resource MyApp.Accounts.User
        end
      end

  Supported fields are intentionally limited:

  - `name`
  - `model`
  - `system_prompt` as a string, module callback, or MFA tuple
  - `schema` as an optional Zoi map/object schema for runtime context
  - `memory`
  - `tools`
  - `subagents`
  - `plugins`
  - `hooks`
  - `guardrails`

  A nested runtime module is generated automatically and uses `Jido.AI.Agent`
  with the configured tool modules. The `tools` block currently supports
  explicit `Moto.Tool` modules and `ash_resource` expansion via `AshJido`.
  The `subagents` block compiles specialist agents into tool-like delegation
  capabilities while keeping the parent agent in control. Subagent entries can
  tune child `timeout`, public `forward_context`, and parent-visible `result`
  shape without introducing handoffs or workflow graphs.
  The `plugins` block accepts `Moto.Plugin` modules and merges their declared
  action-backed tools into the same LLM-visible tool registry.
  """

  @doc false
  @spec prepare_chat_opts(keyword(), map() | nil) :: {:ok, keyword()} | {:error, term()}
  def prepare_chat_opts(opts, config \\ nil) when is_list(opts) do
    Moto.Agent.Chat.prepare_chat_opts(opts, config)
  end

  defmacro __using__(opts \\ []) do
    if opts != [] do
      raise CompileError,
        file: __CALLER__.file,
        line: __CALLER__.line,
        description: "Moto.Agent now uses a Spark DSL. Use `use Moto.Agent` and configure it inside `agent do ... end`."
    end

    quote location: :keep do
      use Moto.Agent.SparkDsl

      @before_compile Moto.Agent
    end
  end

  defmacro __before_compile__(env) do
    Moto.Agent.Build.before_compile(env)
  end
end
