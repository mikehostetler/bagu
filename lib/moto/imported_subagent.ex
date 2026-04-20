defmodule Moto.ImportedSubagent do
  @moduledoc """
  Wraps an imported Moto JSON/YAML agent spec as a Moto-compatible subagent module.

  This gives Elixir-defined manager agents a stable module reference while still
  allowing a delegated specialist to be authored as an imported spec.
  """

  defmacro __using__(opts_ast) do
    opts =
      opts_ast
      |> Code.eval_quoted([], __CALLER__)
      |> elem(0)

    path =
      opts
      |> Keyword.fetch!(:path)
      |> resolve_path(__CALLER__.file)

    dynamic_agent =
      path
      |> Moto.import_agent_file!(Keyword.delete(opts, :path))

    quote location: :keep do
      @moto_imported_subagent unquote(Macro.escape(dynamic_agent))

      @doc false
      @spec dynamic_agent() :: Moto.DynamicAgent.t()
      def dynamic_agent, do: @moto_imported_subagent

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
