defmodule Moto.ImportedAgent.Subagent do
  @moduledoc """
  Embeds an imported JSON/YAML agent as a compiled subagent wrapper.

  This is useful when an Elixir-defined manager agent wants to delegate to a
  specialist authored as an imported spec file.
  """

  @doc """
  Imports the configured spec file and exposes it as a Moto subagent module.
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
      path
      |> Moto.import_agent_file!(Keyword.delete(opts, :path))

    quote location: :keep do
      @moto_imported_subagent unquote(Macro.escape(imported_agent))

      @doc false
      @spec imported_agent() :: Moto.ImportedAgent.t()
      def imported_agent, do: @moto_imported_subagent

      @doc false
      @spec dynamic_agent() :: Moto.ImportedAgent.t()
      def dynamic_agent, do: imported_agent()

      @spec name() :: String.t()
      def name, do: @moto_imported_subagent.spec.name

      @spec runtime_module() :: module()
      def runtime_module, do: @moto_imported_subagent.runtime_module

      @spec start_link(keyword()) :: DynamicSupervisor.on_start_child()
      def start_link(opts \\ []) do
        Moto.start_agent(@moto_imported_subagent, opts)
      end

      @spec chat(pid(), String.t(), keyword()) ::
              {:ok, term()} | {:error, term()} | {:interrupt, Moto.Interrupt.t()}
      def chat(pid, message, opts \\ []) when is_pid(pid) and is_binary(message) do
        Moto.chat(pid, message, opts)
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
