defmodule Jidoka.ImportedAgent.Subagent do
  @moduledoc """
  Embeds an imported JSON/YAML agent as a compiled subagent wrapper.

  This is useful when an Elixir-defined manager agent wants to delegate to a
  specialist authored as an imported spec file.
  """

  @doc """
  Imports the configured spec file and exposes it as a Jidoka subagent module.
  """
  @spec __using__(keyword()) :: Macro.t()

  defmacro __using__(opts_ast) do
    opts =
      opts_ast
      |> Code.eval_quoted([], __CALLER__)
      |> elem(0)

    path =
      opts
      |> Keyword.fetch!(:path)
      |> resolve_path(__CALLER__.file)

    imported_agent =
      case Jidoka.ImportedAgent.import_file(path, Keyword.delete(opts, :path)) do
        {:ok, agent} -> agent
        {:error, reason} -> raise ArgumentError, message: Jidoka.ImportedAgent.format_error(reason)
      end

    quote location: :keep do
      @jidoka_imported_subagent unquote(Macro.escape(imported_agent))

      @doc false
      @spec imported_agent() :: Jidoka.ImportedAgent.t()
      def imported_agent, do: @jidoka_imported_subagent

      @doc false
      @spec dynamic_agent() :: Jidoka.ImportedAgent.t()
      def dynamic_agent, do: imported_agent()

      @spec name() :: String.t()
      def name, do: @jidoka_imported_subagent.spec.id

      @spec runtime_module() :: module()
      def runtime_module, do: @jidoka_imported_subagent.runtime_module

      @spec start_link(keyword()) :: DynamicSupervisor.on_start_child()
      def start_link(opts \\ []) do
        Jidoka.ImportedAgent.start_link(@jidoka_imported_subagent, opts)
      end

      @spec chat(pid(), String.t(), keyword()) ::
              {:ok, term()}
              | {:ok, Jidoka.Chat.Stream.t()}
              | {:error, term()}
              | {:interrupt, Jidoka.Interrupt.t()}
      def chat(pid, message, opts \\ []) when is_pid(pid) and is_binary(message) do
        Jidoka.Chat.chat(pid, message, opts)
      end
    end
  end

  defp resolve_path(path, caller_file) when is_binary(path) do
    if Path.type(path) == :absolute do
      path
    else
      caller_file
      |> Path.dirname()
      |> Path.join(path)
      |> Path.expand()
    end
  end
end
